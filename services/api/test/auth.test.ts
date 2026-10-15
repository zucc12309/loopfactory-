import { beforeAll, describe, expect, it } from 'vitest';
import { api, guest, makeApp, resetDb } from './helpers';

beforeAll(resetDb);

describe('guest authentication', () => {
  it('issues server-generated credentials', async () => {
    const g = await guest();
    expect(g.player.id).toMatch(/[0-9a-f-]{36}/);
    expect(g.refreshToken.length).toBeGreaterThan(40);
    expect(g.player.displayName).toMatch(/\w+ \w+ \d+/);
    const me = await api().get('/api/v1/player/me').set(g.auth).expect(200);
    expect(me.body.id).toBe(g.player.id);
    expect(me.body.linkedProviders).toEqual([]);
  });

  it('rejects missing, malformed and forged tokens', async () => {
    await api().get('/api/v1/player/me').expect(401);
    await api().get('/api/v1/player/me').set('Authorization', 'Bearer nope').expect(401);
    const forged = 'eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiJ4In0.c2lnbmF0dXJl';
    const r = await api().get('/api/v1/player/me').set('Authorization', `Bearer ${forged}`).expect(401);
    expect(r.body.error.code).toBe('invalid_token');
  });

  it('rotates refresh tokens and detects reuse', async () => {
    const g = await guest();
    const r1 = await api().post('/api/v1/auth/refresh').send({ refreshToken: g.refreshToken }).expect(200);
    expect(r1.body.refreshToken).not.toBe(g.refreshToken);
    // Reusing the old token revokes the whole family, including the new token.
    const reuse = await api().post('/api/v1/auth/refresh').send({ refreshToken: g.refreshToken }).expect(401);
    expect(reuse.body.error.code).toBe('refresh_token_reused');
    await api().post('/api/v1/auth/refresh').send({ refreshToken: r1.body.refreshToken }).expect(401);
  });

  it('allows exactly one winner when the same token is rotated concurrently', async () => {
    const g = await guest();
    const results = await Promise.all([1, 2, 3].map(() => api().post('/api/v1/auth/refresh').send({ refreshToken: g.refreshToken })));
    expect(results.filter((r) => r.status === 200).length).toBeLessThanOrEqual(1);
  });

  it('logout revokes the session family', async () => {
    const g = await guest();
    await api().post('/api/v1/auth/logout').set(g.auth).send({ refreshToken: g.refreshToken }).expect(204);
    await api().post('/api/v1/auth/refresh').send({ refreshToken: g.refreshToken }).expect(401);
  });

  it('links an identity and restores the account on a new install', async () => {
    const a = await guest();
    const linked = await api().post('/api/v1/auth/link').set(a.auth).send({ provider: 'dev', idToken: 'dev:alice_1' }).expect(200);
    expect(linked.body.mode).toBe('linked');
    const again = await api().post('/api/v1/auth/link').set(a.auth).send({ provider: 'dev', idToken: 'dev:alice_1' }).expect(200);
    expect(again.body.mode).toBe('already_linked');
    // Reinstall: brand-new guest, same identity.
    const b = await guest();
    const conflict = await api().post('/api/v1/auth/link').set(b.auth).send({ provider: 'dev', idToken: 'dev:alice_1' }).expect(409);
    expect(conflict.body.error.code).toBe('identity_in_use');
    const sw = await api().post('/api/v1/auth/link').set(b.auth).send({ provider: 'dev', idToken: 'dev:alice_1', onConflict: 'switch' }).expect(200);
    expect(sw.body.mode).toBe('switched');
    expect(sw.body.player.id).toBe(a.player.id);
    const me = await api().get('/api/v1/player/me').set('Authorization', `Bearer ${sw.body.tokens.accessToken}`).expect(200);
    expect(me.body.id).toBe(a.player.id);
    expect(me.body.linkedProviders).toEqual(['dev']);
  });

  it('refuses unconfigured providers and dev auth when disabled', async () => {
    const g = await guest();
    const google = await api().post('/api/v1/auth/link').set(g.auth).send({ provider: 'google', idToken: 'x' }).expect(501);
    expect(google.body.error.code).toBe('provider_not_configured');
    const app = makeApp({ devAuth: false });
    const g2 = await guest(app);
    await api(app).post('/api/v1/auth/link').set(g2.auth).send({ provider: 'dev', idToken: 'dev:bob_1' }).expect(501);
  });

  it('rate-limits guest account creation', async () => {
    const app = makeApp({ rateLimitDisabled: false });
    let limited = 0;
    for (let i = 0; i < 32; i++) {
      const r = await api(app).post('/api/v1/auth/guest').send({});
      if (r.status === 429) limited++;
    }
    expect(limited).toBeGreaterThan(0);
  });
});

describe('player profile', () => {
  it('validates and moderates display names', async () => {
    const g = await guest();
    const ok = await api().patch('/api/v1/player/me').set(g.auth).send({ displayName: 'Priya_42' }).expect(200);
    expect(ok.body.displayName).toBe('Priya_42');
    await api().patch('/api/v1/player/me').set(g.auth).send({ displayName: 'x' }).expect(400);
    await api().patch('/api/v1/player/me').set(g.auth).send({ displayName: '<script>' }).expect(400);
    const bad = await api().patch('/api/v1/player/me').set(g.auth).send({ displayName: 'the admin' }).expect(422);
    expect(bad.body.error.code).toBe('name_not_allowed');
    await api().patch('/api/v1/player/me').set(g.auth).send({ displayName: 'Valid Name', extra: 1 }).expect(400);
  });
});
