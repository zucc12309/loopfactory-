import curated from '@loopfactory/engine/levels/curated.json' with { type: 'json' };
import type { Level } from '@loopfactory/engine';
import type { Prisma } from '@prisma/client';
import type { Db } from './db';
import { ACHIEVEMENTS } from './services/achievements';
import { CAMPAIGN_PACK } from './services/levels';
import { DEFAULT_REMOTE_CONFIG } from './routes';

/** Idempotent reference-data seed: campaign levels, achievements, initial remote config. */
export async function seed(db: Db) {
  await db.levelPack.upsert({
    where: { id: CAMPAIGN_PACK },
    create: { id: CAMPAIGN_PACK, name: 'Campaign', description: 'Hand-picked puzzles from first tap to expert.', ordinal: 0 },
    update: {},
  });
  const levels = (curated as unknown as { levels: Level[] }).levels;
  for (const [i, l] of levels.entries()) {
    const data = {
      packId: CAMPAIGN_PACK, ordinal: i, name: l.name, contentVersion: l.version, difficulty: l.difficulty, difficultyScore: l.difficultyScore,
      width: l.width, height: l.height, par: l.par, generatorVersion: l.generator?.version ?? null, seed: l.generator ? BigInt(l.generator.seed) : null,
      definition: l as unknown as Prisma.InputJsonValue,
    };
    await db.level.upsert({ where: { id: l.id }, create: { id: l.id, ...data }, update: data });
  }
  for (const a of ACHIEVEMENTS) {
    await db.achievement.upsert({ where: { id: a.id }, create: a, update: a });
  }
  const anyConfig = await db.remoteConfigVersion.findFirst();
  if (!anyConfig) await db.remoteConfigVersion.create({ data: { version: 1, config: DEFAULT_REMOTE_CONFIG, active: true, note: 'initial' } });
  return { levels: levels.length, achievements: ACHIEVEMENTS.length };
}
