import { beforeAll, describe, expect, it } from 'vitest';
import { api, guest, makeApp, resetDb } from './helpers';

/** Rate limits under carrier-NAT conditions (audit B5/B6). All supertest requests share one IP. */
beforeAll(resetDb);

describe('rate limits', () => {
  it('many legitimate players behind one IP are not throttled together', async () => {
    const plain = makeApp();
    const players = await Promise.all(Array.from({ length: 40 }, () => guest(plain)));
    const app = makeApp({ rateLimitDisabled: false });
    let limited = 0;
    // 40 players x 20 requests = 800 requests from one IP in under a minute (old global cap: 600/IP).
    for (let round = 0; round < 20; round++) {
      const rs = await Promise.all(players.map((p) => api(app).get('/api/v1/player/me').set(p.auth)));
      limited += rs.filter((r) => r.status === 429).length;
    }
    expect(limited).toBe(0);
  });

  it('a single player hammering the API is limited (per player)', async () => {
    const app = makeApp({ rateLimitDisabled: false });
    const p = await guest(makeApp());
    let limited = 0;
    for (let i = 0; i < 70; i++) {
      const r = await api(app).post('/api/v1/progress/sync').set(p.auth).send({ operations: [] });
      if (r.status === 429) limited++;
    }
    expect(limited).toBeGreaterThan(0);
    // ...without affecting another player on the same IP.
    const q = await guest(makeApp());
    await api(app).post('/api/v1/progress/sync').set(q.auth).send({ operations: [] }).expect(200);
  });

  it('anonymous traffic is still limited per IP, and a forged token does not escape it', async () => {
    const app = makeApp({ rateLimitDisabled: false });
    let limited = 0;
    for (let i = 0; i < 620; i++) {
      const r = await api(app).get('/health').set('Authorization', `Bearer forged.${i}.token`);
      if (r.status === 429) limited++;
    }
    expect(limited).toBeGreaterThan(0);
  });

  it('guest creation: burst-capped per IP, sized for NAT', async () => {
    const app = makeApp({ rateLimitDisabled: false });
    const statuses: number[] = [];
    for (let i = 0; i < 24; i++) statuses.push((await api(app).post('/api/v1/auth/guest').send({})).status);
    expect(statuses.slice(0, 20).every((s) => s === 201)).toBe(true);
    expect(statuses.slice(20).every((s) => s === 429)).toBe(true);
  });

  it('refresh is limited per session, not per IP', async () => {
    const app = makeApp({ rateLimitDisabled: false });
    const plain = makeApp();
    const sessions = await Promise.all(Array.from({ length: 15 }, () => guest(plain)));
    // 15 sessions refreshing from one IP: 15 > the per-token cap of 10, yet nobody is limited.
    const rs = await Promise.all(sessions.map((s) => api(app).post('/api/v1/auth/refresh').send({ refreshToken: s.refreshToken })));
    expect(rs.every((r) => r.status === 200)).toBe(true);
  });

  it('limits are per process: a restarted instance starts with fresh counters', async () => {
    const a = makeApp({ rateLimitDisabled: false });
    for (let i = 0; i < 20; i++) await api(a).post('/api/v1/auth/guest').send({});
    await api(a).post('/api/v1/auth/guest').send({}).expect(429);
    const restarted = makeApp({ rateLimitDisabled: false });
    await api(restarted).post('/api/v1/auth/guest').send({}).expect(201);
  });
});
