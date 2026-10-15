import { generateLevel, GENERATOR_VERSION } from '@loopfactory/engine';
import { beforeAll, describe, expect, it } from 'vitest';
import { CODE_ALPHABET, newCode, outcomeOf } from '../src/services/friends';
import { CURATED, api, db, guest, resetDb } from './helpers';

beforeAll(async () => {
  await resetDb();
  await db.$executeRawUnsafe('TRUNCATE friend_challenges CASCADE');
});

const c06 = CURATED.find((l) => l.id === 'c06')!;
const solution = c06.solution.moves;
// A valid but wasteful solve: two extra turns on the first solution tile (+1 then -1).
const wasteful = [[solution[0]![0], 1], [solution[0]![0], -1], ...solution];

describe('friend challenges', () => {
  it('generates readable codes and compares lower-is-better', () => {
    for (let i = 0; i < 200; i++) {
      const c = newCode();
      expect(c).toMatch(/^[A-HJ-NP-Z2-9]{8}$/);
      for (const ch of c) expect(CODE_ALPHABET).toContain(ch);
    }
    expect(outcomeOf(5, 6)).toBe('win');
    expect(outcomeOf(6, 6)).toBe('tie');
    expect(outcomeOf(7, 6)).toBe('lose');
  });

  it('creates a challenge only from a verified solve, and hides the solution and creator moves', async () => {
    const alice = await guest();
    await api().post('/api/v1/challenges/friend').set(alice.auth).send({ level: { type: 'campaign', levelId: 'c06' }, moves: solution.slice(0, -1) }).expect(422);
    await api().post('/api/v1/challenges/friend').send({ level: { type: 'campaign', levelId: 'c06' }, moves: solution }).expect(401);
    const created = await api().post('/api/v1/challenges/friend').set(alice.auth).send({ level: { type: 'campaign', levelId: 'c06' }, moves: wasteful }).expect(201);
    expect(created.body.rotations).toBe(wasteful.length);
    expect(created.body.url).toContain(`/c/${created.body.code}`);
    const view = await api().get(`/api/v1/challenges/friend/${created.body.code.toLowerCase()}`).expect(200);
    expect(view.body.creatorName).toBe(alice.player.displayName);
    expect(view.body.creatorRotations).toBe(wasteful.length);
    expect(view.body.level.solution).toBeUndefined();
    expect(JSON.stringify(view.body)).not.toContain('creatorMoves');
    expect(view.body.level.tiles).toEqual(c06.tiles);
    await api().get('/api/v1/challenges/friend/AAAAAAAA').expect(404);
    await api().get('/api/v1/challenges/friend/bad').expect(400);
  });

  it('verifies attempts server-side and keeps each player best; creator cannot attempt', async () => {
    const alice = await guest();
    const bob = await guest();
    const carol = await guest();
    const { body } = await api().post('/api/v1/challenges/friend').set(alice.auth).send({ level: { type: 'campaign', levelId: 'c06' }, moves: wasteful }).expect(201);
    const code = body.code as string;
    await api().post(`/api/v1/challenges/friend/${code}/attempts`).set(alice.auth).send({ moves: solution }).expect(409);
    // Invalid replay → not counted.
    const bad = await api().post(`/api/v1/challenges/friend/${code}/attempts`).set(bob.auth).send({ moves: solution.slice(1) }).expect(200);
    expect(bad.body).toMatchObject({ valid: false, outcome: null, best: null });
    // Tie, then improve to a win.
    const tie = await api().post(`/api/v1/challenges/friend/${code}/attempts`).set(bob.auth).send({ moves: wasteful }).expect(200);
    expect(tie.body).toMatchObject({ valid: true, outcome: 'tie', best: wasteful.length });
    const win = await api().post(`/api/v1/challenges/friend/${code}/attempts`).set(bob.auth).send({ moves: solution }).expect(200);
    expect(win.body).toMatchObject({ valid: true, outcome: 'win', best: solution.length, creatorRotations: wasteful.length });
    // A worse later attempt doesn't lower the stored best.
    const worse = await api().post(`/api/v1/challenges/friend/${code}/attempts`).set(bob.auth).send({ moves: wasteful }).expect(200);
    expect(worse.body).toMatchObject({ best: solution.length, outcome: 'win' });
    await api().post(`/api/v1/challenges/friend/${code}/attempts`).set(carol.auth).send({ moves: wasteful }).expect(200);
    const results = await api().get(`/api/v1/challenges/friend/${code}/results`).set(bob.auth).expect(200);
    expect(results.body.entries.map((e: { displayName: string }) => e.displayName)).toEqual([bob.player.displayName, alice.player.displayName, carol.player.displayName]);
    expect(results.body.entries[0]).toMatchObject({ rank: 1, isMe: true, isCreator: false });
    expect(results.body.entries[1]).toMatchObject({ isCreator: true });
    const view = await api().get(`/api/v1/challenges/friend/${code}`).expect(200);
    expect(view.body.attempts).toBe(2);
  });

  it('rebuilds generated puzzles from their seed and rejects other generator versions', async () => {
    const lvl = generateLevel(424242, 'easy')!;
    const alice = await guest();
    const ok = await api().post('/api/v1/challenges/friend').set(alice.auth).send({ level: { type: 'generated', seed: lvl.generator!.seed, tier: 'easy', version: GENERATOR_VERSION }, moves: lvl.solution.moves }).expect(201);
    const view = await api().get(`/api/v1/challenges/friend/${ok.body.code}`).expect(200);
    expect(view.body.level.tiles).toEqual(lvl.tiles);
    await api().post('/api/v1/challenges/friend').set(alice.auth).send({ level: { type: 'generated', seed: 1, tier: 'easy', version: 'gen-0' }, moves: lvl.solution.moves }).expect(409);
  });

  it('serves an escaped landing page and expires old challenges', async () => {
    const alice = await guest();
    await api().patch('/api/v1/player/me').set(alice.auth).send({ displayName: 'Ali' }).expect(200);
    const { body } = await api().post('/api/v1/challenges/friend').set(alice.auth).send({ level: { type: 'campaign', levelId: 'c06' }, moves: solution }).expect(201);
    const page = await api().get(`/c/${body.code}`).expect(200);
    expect(page.headers['content-type']).toContain('text/html');
    expect(page.text).toContain(body.code);
    expect(page.text).toContain('Ali');
    expect(page.text).not.toContain('<script');
    await api().get('/c/NOPE').expect(404);
    await db.friendChallenge.update({ where: { code: body.code }, data: { expiresAt: new Date(Date.now() - 1000) } });
    await api().get(`/api/v1/challenges/friend/${body.code}`).expect(404);
    await api().get(`/c/${body.code}`).expect(404);
  });

  it('includes challenges in data export and deletes them with the account', async () => {
    const alice = await guest();
    const bob = await guest();
    const { body } = await api().post('/api/v1/challenges/friend').set(alice.auth).send({ level: { type: 'campaign', levelId: 'c06' }, moves: solution }).expect(201);
    await api().post(`/api/v1/challenges/friend/${body.code}/attempts`).set(bob.auth).send({ moves: solution }).expect(200);
    const exp = await api().get('/api/v1/privacy/export').set(alice.auth).expect(200);
    expect(exp.body.player.friendChallenges[0].code).toBe(body.code);
    await api().post('/api/v1/privacy/delete-request').set(alice.auth).send({ confirm: true }).expect(200);
    expect(await db.friendChallenge.count({ where: { code: body.code } })).toBe(0);
    expect(await db.friendChallengeAttempt.count({ where: { playerId: bob.player.id } })).toBe(0);
  });
});
