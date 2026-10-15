import { createHmac } from 'node:crypto';
import { generateLevelFrom, GENERATOR_VERSION, verifyReplay, type Difficulty, type Level, type Move } from '@loopfactory/engine';
import type { Prisma } from '@prisma/client';
import type { Db } from '../db';
import { isUniqueViolation } from '../db';
import { ApiError } from '../errors';
import { evaluateAchievements } from './achievements';
import { recomputeWeekly, upsertBest } from './leaderboards';

/** Weekday → tier (UTC). Mirrors LFGameState.DAILY_TIERS in the client. Sunday first. */
export const DAILY_TIERS: Difficulty[] = ['expert', 'easy', 'medium', 'medium', 'hard', 'hard', 'expert'];
/** Submissions are ranked until this long after the UTC day ends (covers offline solves). */
export const GRACE_MS = 6 * 3600_000;
/** Past dailies remain downloadable (for offline catch-up) for this many days. */
export const HISTORY_DAYS = 7;

export const todayUtc = (now = new Date()) => now.toISOString().slice(0, 10);
export const dateToUtc = (d: string) => new Date(`${d}T00:00:00.000Z`);

type ChallengeRow = Awaited<ReturnType<Db['dailyChallenge']['findUnique']>> & object;

export class DailyService {
  /** Published dailies are immutable, so they are cached in memory after the first read. */
  private static cache = new Map<string, ChallengeRow>();

  constructor(
    private db: Db,
    private seedSecret: string,
  ) {}

  /** Unpredictable but reproducible seed: HMAC(secret, date). Players can't precompute future dailies. */
  seedFor(date: string): number {
    return createHmac('sha256', this.seedSecret).update(`daily:${date}`).digest().readUInt32BE(0);
  }

  tierFor(date: string): Difficulty {
    return DAILY_TIERS[dateToUtc(date).getUTCDay()]!;
  }

  buildLevel(date: string): Level {
    const lvl = generateLevelFrom(this.seedFor(date), this.tierFor(date), { id: `daily-${date}`, name: `Daily ${date}` });
    if (!lvl) throw new ApiError(500, 'daily_generation_failed', 'Could not generate daily puzzle');
    return lvl;
  }

  /** Get or create (race-safe via the unique date constraint). */
  async getOrCreate(date: string): Promise<ChallengeRow> {
    const key = `${this.seedFor(date)}:${date}`;
    const hit = DailyService.cache.get(key);
    if (hit) return hit;
    const row = await this.fetchOrCreate(date);
    if (DailyService.cache.size > 64) DailyService.cache.clear();
    DailyService.cache.set(key, row);
    return row;
  }

  private async fetchOrCreate(date: string): Promise<ChallengeRow> {
    const existing = await this.db.dailyChallenge.findUnique({ where: { date: dateToUtc(date) } });
    if (existing) return existing;
    const level = this.buildLevel(date);
    try {
      return await this.db.dailyChallenge.create({
        data: { date: dateToUtc(date), tier: level.difficulty, seed: BigInt(level.generator!.seed), generatorVersion: GENERATOR_VERSION, level: level as unknown as Prisma.InputJsonValue, par: level.par },
      });
    } catch (e) {
      if (!isUniqueViolation(e)) throw e;
      return (await this.db.dailyChallenge.findUnique({ where: { date: dateToUtc(date) } }))!;
    }
  }

  assertAvailable(date: string, now = new Date()) {
    const today = todayUtc(now);
    if (date > today) throw new ApiError(404, 'not_published', 'That daily puzzle has not been published yet');
    const ageDays = (dateToUtc(today).getTime() - dateToUtc(date).getTime()) / 86400000;
    if (ageDays > HISTORY_DAYS) throw new ApiError(404, 'expired', 'That daily puzzle is no longer available');
  }

  closesAt(date: string): Date {
    return new Date(dateToUtc(date).getTime() + 86400_000 + GRACE_MS);
  }

  async submit(playerId: string, date: string, moves: Move[], submissionId: string, now = new Date()) {
    this.assertAvailable(date, now);
    if (now.getTime() > this.closesAt(date).getTime()) throw new ApiError(409, 'challenge_closed', 'Submissions for that daily are closed');
    const challenge = await this.getOrCreate(date);
    const prior = await this.db.challengeSubmission.findUnique({ where: { playerId_submissionId: { playerId, submissionId } } });
    if (prior) return { ...(await this.result(playerId, date, prior.valid, prior.rotations, prior.error)), duplicate: true };
    const verdict = verifyReplay(challenge.level as unknown as Level, moves);
    try {
      await this.db.$transaction(async (tx) => {
        await tx.challengeSubmission.create({
          data: { challengeId: challenge.id, playerId, submissionId, moves: moves as unknown as Prisma.InputJsonValue, rotations: verdict.rotations, valid: verdict.valid, error: verdict.error },
        });
        if (verdict.valid) {
          await upsertBest(tx, `daily:${date}`, playerId, verdict.rotations, { rotations: verdict.rotations });
          await recomputeWeekly(tx, playerId, dateToUtc(date));
          await evaluateAchievements(tx, playerId);
        }
      });
    } catch (e) {
      if (!isUniqueViolation(e)) throw e;
    }
    return { ...(await this.result(playerId, date, verdict.valid, verdict.rotations, verdict.error)), duplicate: false };
  }

  private async result(playerId: string, date: string, valid: boolean, rotations: number, error: string | null) {
    const board = `daily:${date}`;
    const entry = await this.db.leaderboardEntry.findUnique({ where: { board_playerId: { board, playerId } } });
    let rank: number | null = null;
    if (entry) rank = 1 + (await this.db.leaderboardEntry.count({ where: { board, OR: [{ score: { lt: entry.score } }, { score: entry.score, achievedAt: { lt: entry.achievedAt } }] } }));
    return { valid, rotations, best: entry?.score ?? null, rank, error };
  }
}
