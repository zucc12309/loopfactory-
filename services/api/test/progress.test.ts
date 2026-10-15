import { beforeAll, describe, expect, it } from 'vitest';
import { CURATED, api, completeOp, db, generateLevel, guest, opId, resetDb, wasteful } from './helpers';

beforeAll(resetDb);
const sync = (auth: Record<string, string>, operations: unknown[]) => api().post('/api/v1/progress/sync').set(auth).send({ operations });

describe('progress sync', () => {
  it('applies a verified completion and returns the snapshot', async () => {
    const g = await guest();
    const lvl = CURATED[3]!;
    const r = await sync(g.auth, [completeOp(lvl, lvl.solution.moves)]).expect(200);
    expect(r.body.results[0].status).toBe('applied');
    const entry = r.body.snapshot.progress.find((p: { levelId: string }) => p.levelId === lvl.id);
    expect(entry).toMatchObject({ bestRotations: lvl.par, verified: true, kind: 'campaign' });
    expect(r.body.snapshot.stats.campaign).toBe(1);
    expect(r.body.snapshot.achievements).toEqual(expect.arrayContaining(['first_delivery', 'efficient']));
  });

  it('is idempotent: duplicate operations are acknowledged but not re-applied', async () => {
    const g = await guest();
    const op = completeOp(CURATED[0]!, CURATED[0]!.solution.moves);
    await sync(g.auth, [op]).expect(200);
    const again = await sync(g.auth, [op]).expect(200);
    expect(again.body.results[0].status).toBe('duplicate');
    const row = await db.playerLevelProgress.findFirstOrThrow({ where: { playerId: g.player.id } });
    expect(row.completions).toBe(1);
  });

  it('handles the same batch arriving concurrently (flaky network retries)', async () => {
    const g = await guest();
    const op = completeOp(CURATED[1]!, CURATED[1]!.solution.moves);
    const rs = await Promise.all([1, 2, 3, 4].map(() => sync(g.auth, [op])));
    expect(rs.every((r) => r.status === 200)).toBe(true);
    const statuses = rs.map((r) => r.body.results[0].status).sort();
    expect(statuses.filter((s) => s === 'applied').length).toBe(1);
    expect(await db.syncOperation.count({ where: { playerId: g.player.id } })).toBe(1);
    const row = await db.playerLevelProgress.findFirstOrThrow({ where: { playerId: g.player.id } });
    expect(row.completions).toBe(1);
  });

  it('rejects forged replays and unknown levels', async () => {
    const g = await guest();
    const lvl = CURATED[5]!;
    const r = await sync(g.auth, [
      completeOp(lvl, lvl.solution.moves.slice(1)),
      completeOp({ ...lvl, id: 'nope' }, lvl.solution.moves),
      completeOp(lvl, [[0, 1]]),
    ]).expect(200);
    expect(r.body.results.map((x: { error: string }) => x.error)).toEqual(['replay_not_solved', 'unknown_level', 'replay_illegal_move']);
    expect(r.body.snapshot.progress).toEqual([]);
  });

  it('keeps unverified completions but never ranks them or lets them beat par', async () => {
    const g = await guest();
    const lvl = CURATED[8]!;
    const r = await sync(g.auth, [completeOp(lvl, null, { rotations: 0 })]).expect(200);
    const e = r.body.snapshot.progress[0];
    expect(e).toMatchObject({ verified: false, bestRotations: lvl.par });
    expect(await db.leaderboardEntry.count({ where: { playerId: g.player.id } })).toBe(0);
    // A later verified replay upgrades the record.
    const r2 = await sync(g.auth, [completeOp(lvl, wasteful(lvl))]).expect(200);
    expect(r2.body.snapshot.progress[0]).toMatchObject({ verified: true, bestRotations: lvl.par + 2 });
    const r3 = await sync(g.auth, [completeOp(lvl, lvl.solution.moves)]).expect(200);
    expect(r3.body.snapshot.progress[0].bestRotations).toBe(lvl.par);
    expect(await db.leaderboardEntry.count({ where: { playerId: g.player.id, board: 'global' } })).toBe(1);
  });

  it('completions are monotonic and best = min (offline play then sync)', async () => {
    const g = await guest();
    const lvl = CURATED[10]!;
    // Played three times offline; the queue uploads them out of order.
    const ops = [completeOp(lvl, wasteful(lvl, 4)), completeOp(lvl, lvl.solution.moves), completeOp(lvl, wasteful(lvl, 2))];
    const r = await sync(g.auth, ops).expect(200);
    expect(r.body.results.every((x: { status: string }) => x.status === 'applied')).toBe(true);
    expect(r.body.snapshot.progress[0].bestRotations).toBe(lvl.par);
    const row = await db.playerLevelProgress.findFirstOrThrow({ where: { playerId: g.player.id } });
    expect(row.completions).toBe(3);
  });

  it('settings use last-writer-wins on client timestamps (multi-device)', async () => {
    const g = await guest();
    const s = (sfx: boolean, updatedAt: number) => ({ opId: opId(), type: 'settings', clientTs: updatedAt, payload: { settings: { sfx, haptics: true }, updatedAt } });
    await sync(g.auth, [s(false, 2000)]).expect(200);
    const stale = await sync(g.auth, [s(true, 1000)]).expect(200); // older device comes online later
    expect(stale.body.snapshot.settings).toMatchObject({ sfx: false, updatedAt: 2000 });
    const newer = await sync(g.auth, [s(true, 3000)]).expect(200);
    expect(newer.body.snapshot.settings).toMatchObject({ sfx: true, updatedAt: 3000 });
  });

  it('strips unknown settings keys', async () => {
    const g = await guest();
    const r = await sync(g.auth, [{ opId: opId(), type: 'settings', clientTs: 1, payload: { settings: { sfx: true, evil: 'x' }, updatedAt: 5 } }]).expect(200);
    expect(r.body.snapshot.settings).not.toHaveProperty('evil');
  });

  it('active puzzle uses last-writer-wins', async () => {
    const g = await guest();
    const a = (levelId: string, updatedAt: number) => ({ opId: opId(), type: 'active_puzzle', clientTs: updatedAt, payload: { kind: 'campaign', levelId, rotations: [0, 1], history: [[1, 1]], updatedAt } });
    await sync(g.auth, [a('c05', 200)]).expect(200);
    const r = await sync(g.auth, [a('c04', 100)]).expect(200);
    expect(r.body.snapshot.activePuzzle.levelId).toBe('c05');
  });

  it('verifies endless completions by regenerating the level from its seed', async () => {
    const g = await guest();
    const lvl = generateLevel(4242, 'medium')!;
    const op = { opId: opId(), type: 'level_complete', clientTs: 1, payload: { kind: 'endless', levelId: lvl.id, contentVersion: 1, moves: lvl.solution.moves, rotations: lvl.par, hints: 0, completedAt: 1, generator: lvl.generator } };
    const r = await sync(g.auth, [op]).expect(200);
    expect(r.body.results[0].status).toBe('applied');
    expect(r.body.snapshot.stats.endless).toBe(1);
    const bad = { ...op, opId: opId(), payload: { ...op.payload, generator: { ...lvl.generator, seed: 4243 } } };
    const r2 = await sync(g.auth, [bad]).expect(200);
    expect(r2.body.results[0].status).toBe('rejected');
  });

  it('validates request shape and size', async () => {
    const g = await guest();
    await sync(g.auth, [{ opId: 'short', type: 'settings', clientTs: 1, payload: {} }]).expect(400);
    await sync(g.auth, Array.from({ length: 101 }, () => completeOp(CURATED[0]!, null))).expect(400);
    const r = await api().post('/api/v1/progress/sync').set(g.auth).set('Content-Type', 'application/json').send('{bad json').expect(400);
    expect(r.body.error.code).toBe('invalid_json');
  });

  it('history pages newest first', async () => {
    const g = await guest();
    await sync(g.auth, CURATED.slice(0, 3).map((l) => completeOp(l, l.solution.moves))).expect(200);
    const h = await api().get('/api/v1/progress/history?limit=2').set(g.auth).expect(200);
    expect(h.body.items).toHaveLength(2);
    expect(h.body.nextBefore).not.toBeNull();
  });

  it('isolates players from each other', async () => {
    const a = await guest();
    const b = await guest();
    await sync(a.auth, [completeOp(CURATED[0]!, CURATED[0]!.solution.moves)]).expect(200);
    const snap = await api().get('/api/v1/progress').set(b.auth).expect(200);
    expect(snap.body.progress).toEqual([]);
  });
});
