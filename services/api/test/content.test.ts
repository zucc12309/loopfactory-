import { beforeAll, describe, expect, it } from 'vitest';
import { DailyService } from '../src/services/daily';
import { CURATED, api, completeOp, config, db, guest, resetDb, wasteful } from './helpers';

beforeAll(resetDb);
const today = new Date().toISOString().slice(0, 10);

describe('levels', () => {
  it('lists, paginates and fetches levels; specific routes are not shadowed by :id', async () => {
    const page1 = await api().get('/api/v1/levels?limit=10').expect(200);
    expect(page1.body.levels).toHaveLength(10);
    const page2 = await api().get(`/api/v1/levels?limit=50&cursor=${page1.body.nextCursor}`).expect(200);
    expect(page1.body.levels.length + page2.body.levels.length).toBe(CURATED.length);
    const packs = await api().get('/api/v1/levels/packs').expect(200);
    expect(packs.body.packs[0].levelIds).toHaveLength(CURATED.length);
    const one = await api().get('/api/v1/levels/c07').expect(200);
    expect(one.body.tiles).toHaveLength(one.body.width * one.body.height);
    await api().get('/api/v1/levels/zzz').expect(404);
  });
});

describe('daily challenge', () => {
  it('publishes a reproducible puzzle without its solution and hides future days', async () => {
    const a = await api().get('/api/v1/challenges/daily').expect(200);
    const b = await api().get(`/api/v1/challenges/daily?date=${today}`).expect(200);
    expect(a.body.level).toEqual(b.body.level);
    expect(a.body.level.solution).toBeUndefined();
    expect(a.body.date).toBe(today);
    const tomorrow = new Date(Date.now() + 86400_000).toISOString().slice(0, 10);
    await api().get(`/api/v1/challenges/daily?date=${tomorrow}`).expect(404);
    const svc = new DailyService(db, config.dailySeedSecret);
    expect(svc.buildLevel(today).tiles).toEqual(a.body.level.tiles);
    expect(new DailyService(db, 'another-secret-value').seedFor(today)).not.toBe(svc.seedFor(today));
  });

  it('validates submissions server-side and ranks by verified rotations', async () => {
    const ch = await db.dailyChallenge.findFirstOrThrow({ where: { date: new Date(`${today}T00:00:00Z`) } });
    const lvl = ch.level as unknown as (typeof CURATED)[number];
    const p1 = await guest();
    const p2 = await guest();
    const p3 = await guest();
    const submit = (g: typeof p1, moves: unknown, id: string) => api().post('/api/v1/challenges/daily/submit').set(g.auth).send({ date: today, moves, submissionId: id });

    const s1 = await submit(p1, wasteful(lvl, 2), 'sub-p1-aaaa').expect(200);
    expect(s1.body).toMatchObject({ valid: true, rotations: lvl.par + 2, rank: 1, duplicate: false });
    const s2 = await submit(p2, lvl.solution.moves, 'sub-p2-aaaa').expect(200);
    expect(s2.body).toMatchObject({ valid: true, rotations: lvl.par, rank: 1 });
    const bad = await submit(p3, lvl.solution.moves.slice(0, -1), 'sub-p3-aaaa').expect(200);
    expect(bad.body).toMatchObject({ valid: false, error: 'not_solved', rank: null });
    const dup = await submit(p2, lvl.solution.moves, 'sub-p2-aaaa').expect(200);
    expect(dup.body.duplicate).toBe(true);
    // p1 improves to par but later than p2 -> tie broken by time.
    await submit(p1, lvl.solution.moves, 'sub-p1-bbbb').expect(200);

    const lb = await api().get(`/api/v1/challenges/daily/leaderboard?date=${today}`).set(p1.auth).expect(200);
    expect(lb.body.entries.map((e: { displayName: string }) => e.displayName)).toEqual([p2.player.displayName, p1.player.displayName]);
    expect(lb.body.entries[1].isMe).toBe(true);
    expect(lb.body.me.rank).toBe(2);
    const weekly = await api().get('/api/v1/leaderboards/weekly').expect(200);
    expect(weekly.body.entries.length).toBe(2);
    const ach = await api().get('/api/v1/achievements/me').set(p2.auth).expect(200);
    expect(ach.body.achievements.map((a: { id: string }) => a.id)).toContain('daily_debut');
    await submit(p3, [[999, 1]], 'sub-p3-bbbb').expect(400);
  });

  it('closes submissions after the grace period', async () => {
    const g = await guest();
    const svc = new DailyService(db, config.dailySeedSecret);
    const ch = await svc.getOrCreate(today);
    const lvl = ch.level as unknown as (typeof CURATED)[number];
    const late = new Date(svc.closesAt(today).getTime() + 1000);
    await expect(svc.submit(g.player.id, today, lvl.solution.moves, 'late-sub-1', late)).rejects.toMatchObject({ code: 'challenge_closed' });
  });
});

describe('leaderboards', () => {
  it('global ranking counts only verified campaign solves', async () => {
    const a = await guest();
    const b = await guest();
    const sync = (g: typeof a, ops: unknown[]) => api().post('/api/v1/progress/sync').set(g.auth).send({ operations: ops }).expect(200);
    await sync(a, CURATED.slice(0, 3).map((l) => completeOp(l, l.solution.moves)));
    await sync(b, CURATED.slice(0, 2).map((l) => completeOp(l, l.solution.moves)));
    await sync(b, CURATED.slice(5, 9).map((l) => completeOp(l, null))); // unverified
    const lb = await api().get('/api/v1/leaderboards/global?limit=50').set(b.auth).expect(200);
    const names = lb.body.entries.map((e: { displayName: string }) => e.displayName);
    expect(names.indexOf(a.player.displayName)).toBeLessThan(names.indexOf(b.player.displayName));
    expect(lb.body.me.solved).toBe(2);
  });
});

describe('achievements, config and docs', () => {
  it('serves definitions', async () => {
    const r = await api().get('/api/v1/achievements').expect(200);
    expect(r.body.achievements.length).toBeGreaterThanOrEqual(10);
  });
  it('serves remote config with ETag caching', async () => {
    const r = await api().get('/api/v1/config').expect(200);
    expect(r.body.config.hintsEnabled).toBe(true);
    await api().get('/api/v1/config').set('If-None-Match', r.headers.etag!).expect(304);
  });
  it('publishes an OpenAPI 3.1 document covering every required endpoint', async () => {
    const r = await api().get('/openapi.json').expect(200);
    expect(r.body.openapi).toBe('3.1.0');
    const required = [
      'post /api/v1/auth/guest', 'post /api/v1/auth/refresh', 'post /api/v1/auth/link', 'post /api/v1/auth/logout',
      'get /api/v1/player/me', 'patch /api/v1/player/me', 'delete /api/v1/player/me',
      'get /api/v1/progress', 'post /api/v1/progress/sync', 'get /api/v1/progress/history',
      'get /api/v1/levels', 'get /api/v1/levels/{id}', 'get /api/v1/levels/packs',
      'get /api/v1/challenges/daily', 'post /api/v1/challenges/daily/submit', 'get /api/v1/challenges/daily/leaderboard',
      'get /api/v1/leaderboards/global', 'get /api/v1/leaderboards/weekly', 'get /api/v1/leaderboards/daily',
      'get /api/v1/achievements', 'get /api/v1/achievements/me', 'get /api/v1/config',
      'get /api/v1/privacy/export', 'post /api/v1/privacy/delete-request',
    ];
    for (const key of required) {
      const [m, p] = key.split(' ') as [string, string];
      expect(r.body.paths[p]?.[m], key).toBeDefined();
    }
  });
  it('uses a consistent error envelope', async () => {
    const r = await api().get('/api/v1/nope').expect(404);
    expect(r.body.error).toMatchObject({ code: 'not_found' });
    expect(r.body.error.requestId).toBeTruthy();
    const h = await api().get('/health').expect(200);
    expect(h.body.status).toBe('ok');
    await api().get('/ready').expect(200);
  });
});
