import { GENERATOR_VERSION, generateLevel, type Level } from '@loopfactory/engine';
import type { Db } from '../db';

export const CAMPAIGN_PACK = 'campaign';

export function publicLevel(level: Level, includeSolution: boolean): Level {
  if (includeSolution) return level;
  const { solution: _s, solutionCount: _c, solutionCountCapped: _cc, ...rest } = level;
  return rest as Level;
}

export class LevelService {
  private cache = new Map<string, { level: Level; version: number }>();
  constructor(private db: Db) {}

  async get(id: string): Promise<{ level: Level; version: number } | null> {
    const hit = this.cache.get(id);
    if (hit) return hit;
    const row = await this.db.level.findUnique({ where: { id } });
    if (!row) return null;
    const v = { level: row.definition as unknown as Level, version: row.contentVersion };
    this.cache.set(id, v);
    return v;
  }

  /** Regenerate an endless level from its generator reference (deterministic), or null. */
  endless(ref: { version: string; seed: number; tier: Level['difficulty'] }): Level | null {
    if (ref.version !== GENERATOR_VERSION) return null;
    return generateLevel(ref.seed, ref.tier);
  }
}
