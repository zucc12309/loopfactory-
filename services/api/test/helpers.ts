import supertest from 'supertest';
import { generateLevel, type Level, type Move } from '@loopfactory/engine';
import curated from '@loopfactory/engine/levels/curated.json' with { type: 'json' };
import { createApp } from '../src/app';
import { loadConfig } from '../src/config';
import { createDb } from '../src/db';
import { createLogger } from '../src/logger';
import { seed } from '../src/seed';

export const config = loadConfig();
export const db = createDb(config.databaseUrl);
export const CURATED = (curated as unknown as { levels: Level[] }).levels;

export function makeApp(overrides: Partial<typeof config> = {}) {
  return createApp({ config: { ...config, rateLimitDisabled: true, ...overrides }, db, logger: createLogger('silent') });
}
export const api = (app = makeApp()) => supertest(app);

export async function resetDb() {
  await db.$executeRawUnsafe(`TRUNCATE players, daily_challenges, leaderboard_entries, privacy_requests, sync_operations, refresh_tokens CASCADE`);
  await seed(db);
}

export async function guest(app = makeApp()) {
  const res = await supertest(app).post('/api/v1/auth/guest').send({ platform: 'test' }).expect(201);
  return { ...(res.body as { accessToken: string; refreshToken: string; player: { id: string; displayName: string } }), auth: { Authorization: `Bearer ${res.body.accessToken}` } };
}

let n = 0;
export const opId = () => `op-${Date.now()}-${n++}-${Math.random().toString(36).slice(2, 8)}`;

export function completeOp(level: Level, moves: Move[] | null, extra: Record<string, unknown> = {}) {
  return {
    opId: opId(),
    type: 'level_complete',
    clientTs: Date.now(),
    payload: { kind: 'campaign', levelId: level.id, contentVersion: level.version, moves, rotations: moves ? moves.length : level.par, hints: 0, completedAt: Date.now(), ...extra },
  };
}

export function wasteful(level: Level, extra = 2): Move[] {
  const i = level.solution.moves[0]![0];
  const pad: Move[] = [];
  for (let k = 0; k < extra / 2; k++) pad.push([i, 1], [i, -1]);
  return [...pad, ...level.solution.moves];
}

export { generateLevel };
