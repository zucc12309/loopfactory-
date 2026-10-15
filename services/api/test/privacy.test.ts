import { beforeAll, describe, expect, it } from 'vitest';
import { CURATED, api, completeOp, db, guest, resetDb } from './helpers';

beforeAll(resetDb);

describe('privacy', () => {
  it('exports personal data without credentials', async () => {
    const g = await guest();
    await api().post('/api/v1/progress/sync').set(g.auth).send({ operations: [completeOp(CURATED[0]!, CURATED[0]!.solution.moves)] }).expect(200);
    const r = await api().get('/api/v1/privacy/export').set(g.auth).expect(200);
    expect(r.body.player.id).toBe(g.player.id);
    expect(r.body.player.progress).toHaveLength(1);
    expect(JSON.stringify(r.body)).not.toContain(g.refreshToken);
    expect(JSON.stringify(r.body)).not.toContain('tokenHash');
  });

  it('erases the account and everything linked to it', async () => {
    const g = await guest();
    await api().post('/api/v1/progress/sync').set(g.auth).send({ operations: [completeOp(CURATED[0]!, CURATED[0]!.solution.moves)] }).expect(200);
    await api().post('/api/v1/privacy/delete-request').set(g.auth).send({}).expect(400); // explicit confirm required
    const r = await api().post('/api/v1/privacy/delete-request').set(g.auth).send({ confirm: true }).expect(200);
    expect(r.body.status).toBe('completed');
    expect(await db.player.count({ where: { id: g.player.id } })).toBe(0);
    expect(await db.playerLevelProgress.count({ where: { playerId: g.player.id } })).toBe(0);
    expect(await db.leaderboardEntry.count({ where: { playerId: g.player.id } })).toBe(0);
    await api().post('/api/v1/auth/refresh').send({ refreshToken: g.refreshToken }).expect(401);
    const pr = await db.privacyRequest.findUniqueOrThrow({ where: { id: r.body.requestId } });
    expect(pr.subjectHash).not.toContain(g.player.id);
  });

  it('DELETE /player/me also erases', async () => {
    const g = await guest();
    await api().delete('/api/v1/player/me').set(g.auth).expect(204);
    await api().get('/api/v1/player/me').set(g.auth).expect(404);
  });
});

describe('purchases', () => {
  it('verifies purchases server-side and restores entitlements', async () => {
    const g = await guest();
    const r = await api().post('/api/v1/purchases/verify').set(g.auth).send({ store: 'dev', productId: 'remove_ads', purchaseToken: 'dev-ok-abc123' }).expect(200);
    expect(r.body.entitlements).toEqual([expect.objectContaining({ productId: 'remove_ads', status: 'active' })]);
    // Idempotent re-verification (restore)
    await api().post('/api/v1/purchases/verify').set(g.auth).send({ store: 'dev', productId: 'remove_ads', purchaseToken: 'dev-ok-abc123' }).expect(200);
    const list = await api().get('/api/v1/purchases/entitlements').set(g.auth).expect(200);
    expect(list.body.entitlements).toHaveLength(1);
    const other = await guest();
    await api().post('/api/v1/purchases/verify').set(other.auth).send({ store: 'dev', productId: 'remove_ads', purchaseToken: 'dev-ok-abc123' }).expect(409);
    await api().post('/api/v1/purchases/verify').set(g.auth).send({ store: 'dev', productId: 'remove_ads', purchaseToken: 'forged' }).expect(402);
    const gp = await api().post('/api/v1/purchases/verify').set(g.auth).send({ store: 'google_play', productId: 'remove_ads', purchaseToken: 'x' }).expect(501);
    expect(gp.body.error.code).toBe('store_not_configured');
  });
});
