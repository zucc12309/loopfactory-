import { beforeAll, describe, expect, it } from 'vitest';
import { lockedTransaction } from '../src/db';
import { DailyService, todayUtc } from '../src/services/daily';
import { upsertBest } from '../src/services/leaderboards';
import { CURATED, api, completeOp, config, db, guest, makeApp, resetDb, wasteful } from './helpers';

/**
 * Concurrency regressions against a real PostgreSQL database (audit R4/B3, R3 server side).
 * Every request in a Promise.all runs on its own connection, so they genuinely race.
 */
beforeAll(resetDb);

const lvl = CURATED.find((l) => l.id === 'c06')!;
const shuffle = <T>(a: T[]) => a.map((v) => [Math.random(), v] as const).sort((x, y) => x[0] - y[0]).map((x) => x[1]);

async function globalEntry(playerId: string) {
  return db.leaderboardEntry.findUnique({ where: { board_playerId: { board: 'global', playerId } } });
}

describe('score writes under contention', () => {
  it('upsertBest keeps the minimum whatever order racing writes commit in', async () => {
    const g = await guest();
    const scores = shuffle([9, 7, 12, 5, 8, 5, 11, 6]);
    await Promise.all(scores.map((s) => db.$transaction((tx) => upsertBest(tx, 'daily:2099-01-01', g.player.id, s, { rotations: s }))));
    const row = await db.leaderboardEntry.findUniqueOrThrow({ where: { board_playerId: { board: 'daily:2099-01-01', playerId: g.player.id } } });
    expect(row.score).toBe(5);
    expect(row.display).toEqual({ rotations: 5 });
  });

  it('simultaneous first submissions create exactly one row', async () => {
    const g = await guest();
    await Promise.all([4, 3, 6].map((s) => db.$transaction((tx) => upsertBest(tx, 'daily:2099-01-02', g.player.id, s, { rotations: s }))));
    expect(await db.leaderboardEntry.count({ where: { board: 'daily:2099-01-02', playerId: g.player.id } })).toBe(1);
  });

  it('better and worse completions racing in one sync batch each keep the true best', async () => {
    const g = await guest();
    const app = makeApp();
    const ops = shuffle([wasteful(lvl, 6), lvl.solution.moves, wasteful(lvl, 2), wasteful(lvl, 4)]).map((m) => completeOp(lvl, m));
    const results = await Promise.all(ops.map((op) => api(app).post('/api/v1/progress/sync').set(g.auth).send({ operations: [op] })));
    for (const r of results) expect(r.status).toBe(200);
    for (const r of results) expect(r.body.results[0].status).toBe('applied'); // none lost as a fake "duplicate"
    const row = await db.playerLevelProgress.findUniqueOrThrow({ where: { playerId_kind_levelKey: { playerId: g.player.id, kind: 'campaign', levelKey: lvl.id } } });
    expect(row.bestRotations).toBe(lvl.par);
    expect(row.completions).toBe(4);
    expect(row.verified).toBe(true);
    const entry = await globalEntry(g.player.id);
    expect(entry?.display).toEqual({ solved: 1, rotations: lvl.par });
  });

  it('reversed completion order cannot regress the stored best', async () => {
    const g = await guest();
    await api().post('/api/v1/progress/sync').set(g.auth).send({ operations: [completeOp(lvl, lvl.solution.moves)] }).expect(200);
    await api().post('/api/v1/progress/sync').set(g.auth).send({ operations: [completeOp(lvl, wasteful(lvl, 4))] }).expect(200);
    const row = await db.playerLevelProgress.findFirstOrThrow({ where: { playerId: g.player.id, levelKey: lvl.id } });
    expect(row.bestRotations).toBe(lvl.par);
  });

  it('aggregate (global) stays consistent when different levels complete concurrently', async () => {
    const g = await guest();
    const levels = CURATED.slice(0, 6);
    await Promise.all(levels.map((l) => api().post('/api/v1/progress/sync').set(g.auth).send({ operations: [completeOp(l, l.solution.moves)] }).expect(200)));
    const entry = await globalEntry(g.player.id);
    const rotations = levels.reduce((s, l) => s + l.par, 0);
    expect(entry?.display).toEqual({ solved: 6, rotations });
    expect(entry?.score).toBe(-6 * 100000 + rotations);
  });

  it('the same op retried concurrently applies once', async () => {
    const g = await guest();
    const op = completeOp(lvl, lvl.solution.moves);
    const rs = await Promise.all([1, 2, 3, 4].map(() => api().post('/api/v1/progress/sync').set(g.auth).send({ operations: [op] })));
    const statuses = rs.map((r) => r.body.results[0].status).sort();
    expect(statuses).toEqual(['applied', 'duplicate', 'duplicate', 'duplicate']);
    const row = await db.playerLevelProgress.findFirstOrThrow({ where: { playerId: g.player.id, levelKey: lvl.id } });
    expect(row.completions).toBe(1);
  });

  it('lockedTransaction rolls back on error and retries only retryable failures (bounded)', async () => {
    const g = await guest();
    let calls = 0;
    await expect(
      lockedTransaction(db, [`player:${g.player.id}`], async (tx) => {
        calls++;
        await upsertBest(tx, 'daily:2099-02-01', g.player.id, 1, { rotations: 1 });
        throw new Error('boom');
      }),
    ).rejects.toThrow('boom');
    expect(calls).toBe(1);
    expect(await db.leaderboardEntry.count({ where: { board: 'daily:2099-02-01' } })).toBe(0);
    calls = 0;
    await expect(
      lockedTransaction(db, ['k'], async () => {
        calls++;
        throw Object.assign(new Error('serialization'), { code: 'P2034' });
      }),
    ).rejects.toThrow('serialization');
    expect(calls).toBe(3);
  });
});

describe('daily submissions under contention', () => {
  const today = todayUtc();
  const daily = async () => {
    await api().get(`/api/v1/challenges/daily?date=${today}`).expect(200);
    const ch = await db.dailyChallenge.findFirstOrThrow({ where: { date: new Date(`${today}T00:00:00Z`) } });
    return ch.level as unknown as (typeof CURATED)[number];
  };
  const submit = (auth: Record<string, string>, moves: unknown, id: string, date = today) => api().post('/api/v1/challenges/daily/submit').set(auth).send({ date, moves, submissionId: id });

  it('parallel submissions of different quality leave the best on the board, each reported truthfully', async () => {
    const level = await daily();
    const g = await guest();
    const rs = await Promise.all(shuffle([wasteful(level, 4), level.solution.moves, wasteful(level, 2)]).map((m, i) => submit(g.auth, m, `par-${g.player.id.slice(0, 8)}-${i}`)));
    for (const r of rs) expect(r.status).toBe(200);
    for (const r of rs) expect(r.body.duplicate).toBe(false);
    const entry = await db.leaderboardEntry.findUniqueOrThrow({ where: { board_playerId: { board: `daily:${today}`, playerId: g.player.id } } });
    expect(entry.score).toBe(level.par);
    const weekly = await db.leaderboardEntry.findFirstOrThrow({ where: { playerId: g.player.id, board: { startsWith: 'weekly:' } } });
    expect(weekly.display).toEqual({ solved: 1, rotations: level.par });
  });

  it('the same submission id sent concurrently is stored once and answered from committed state', async () => {
    const level = await daily();
    const g = await guest();
    const id = `dup-${g.player.id.slice(0, 8)}`;
    const rs = await Promise.all([1, 2, 3].map(() => submit(g.auth, level.solution.moves, id)));
    for (const r of rs) expect(r.status).toBe(200);
    expect(rs.filter((r) => r.body.duplicate === false).length).toBe(1);
    for (const r of rs) expect(r.body).toMatchObject({ valid: true, rotations: level.par, best: level.par });
    expect(await db.challengeSubmission.count({ where: { playerId: g.player.id, submissionId: id } })).toBe(1);
  });

  it('a duplicate id answers with the stored result, not the resent moves', async () => {
    const level = await daily();
    const g = await guest();
    const id = `stored-${g.player.id.slice(0, 8)}`;
    await submit(g.auth, wasteful(level, 2), id).expect(200);
    const again = await submit(g.auth, level.solution.moves, id).expect(200);
    expect(again.body).toMatchObject({ duplicate: true, rotations: level.par + 2, best: level.par + 2 });
  });

  it('reusing a submission id for a different date is refused', async () => {
    const level = await daily();
    const g = await guest();
    const id = `xdate-${g.player.id.slice(0, 8)}`;
    // First used (through the service, inside its window) for yesterday's daily, then resent for today.
    const yesterday = new Date(Date.now() - 86400_000).toISOString().slice(0, 10);
    const svc = new DailyService(db, config.dailySeedSecret);
    const old = svc.buildLevel(yesterday);
    await svc.submit(g.player.id, yesterday, old.solution.moves, id, new Date(`${yesterday}T12:00:00Z`));
    const r = await submit(g.auth, level.solution.moves, id);
    expect(r.status).toBe(409);
    expect(r.body.error.code).toBe('submission_id_reused');
  });
});

describe('friend challenge attempts under contention', () => {
  it('parallel attempts keep the minimum and count every try', async () => {
    const alice = await guest();
    const bob = await guest();
    const created = await api().post('/api/v1/challenges/friend').set(alice.auth).send({ level: { type: 'campaign', levelId: lvl.id }, moves: wasteful(lvl, 2) }).expect(201);
    const code = created.body.code as string;
    const moves = shuffle([wasteful(lvl, 6), lvl.solution.moves, wasteful(lvl, 4), wasteful(lvl, 2)]);
    const rs = await Promise.all(moves.map((m) => api().post(`/api/v1/challenges/friend/${code}/attempts`).set(bob.auth).send({ moves: m })));
    for (const r of rs) expect(r.status).toBe(200);
    const row = await db.friendChallengeAttempt.findFirstOrThrow({ where: { playerId: bob.player.id } });
    expect(row.rotations).toBe(lvl.par);
    expect(row.tries).toBe(4);
    expect(await db.friendChallengeAttempt.count({ where: { playerId: bob.player.id } })).toBe(1);
  });
});

describe('refresh token recovery (lost response)', () => {
  it('a retry after a lost response recovers the same player and revokes the unused successor', async () => {
    const g = await guest();
    const lost = await api().post('/api/v1/auth/refresh').send({ refreshToken: g.refreshToken }).expect(200); // response "lost"
    const retry = await api().post('/api/v1/auth/refresh').send({ refreshToken: g.refreshToken }).expect(200);
    const me = await api().get('/api/v1/player/me').set('Authorization', `Bearer ${retry.body.accessToken}`).expect(200);
    expect(me.body.id).toBe(g.player.id);
    // The successor that never arrived is dead; the recovered one keeps working.
    await api().post('/api/v1/auth/refresh').send({ refreshToken: lost.body.refreshToken }).expect(401);
  });

  it('reuse after the successor was used is still treated as theft', async () => {
    const g = await guest();
    const r1 = await api().post('/api/v1/auth/refresh').send({ refreshToken: g.refreshToken }).expect(200);
    const r2 = await api().post('/api/v1/auth/refresh').send({ refreshToken: r1.body.refreshToken }).expect(200);
    const reuse = await api().post('/api/v1/auth/refresh').send({ refreshToken: g.refreshToken }).expect(401);
    expect(reuse.body.error.code).toBe('refresh_token_reused');
    await api().post('/api/v1/auth/refresh').send({ refreshToken: r2.body.refreshToken }).expect(401);
  });

  it('no grace outside the window', async () => {
    const g = await guest();
    await api().post('/api/v1/auth/refresh').send({ refreshToken: g.refreshToken }).expect(200);
    await db.refreshToken.updateMany({ where: { playerId: g.player.id, rotatedAt: { not: null } }, data: { rotatedAt: new Date(Date.now() - 10 * 60_000) } });
    const r = await api().post('/api/v1/auth/refresh').send({ refreshToken: g.refreshToken }).expect(401);
    expect(r.body.error.code).toBe('refresh_token_reused');
  });

  it('grace disabled (0) restores strict single use', async () => {
    const app = makeApp({ refreshReuseGraceSeconds: 0 });
    const g = await guest(app);
    await api(app).post('/api/v1/auth/refresh').send({ refreshToken: g.refreshToken }).expect(200);
    await api(app).post('/api/v1/auth/refresh').send({ refreshToken: g.refreshToken }).expect(401);
  });

  it('concurrent rotations of one token leave exactly one live token and never revoke the family', async () => {
    const g = await guest();
    const rs = await Promise.all([1, 2, 3, 4, 5].map(() => api().post('/api/v1/auth/refresh').send({ refreshToken: g.refreshToken })));
    expect(rs.filter((r) => r.status === 200).length).toBeGreaterThanOrEqual(1);
    const live = await db.refreshToken.count({ where: { playerId: g.player.id, rotatedAt: null, revokedAt: null } });
    expect(live).toBe(1);
  });
});
