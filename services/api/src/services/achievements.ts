import defs from '@loopfactory/contracts/data/achievements.json' with { type: 'json' };
import type { Prisma } from '@prisma/client';

type Tx = Prisma.TransactionClient;
export const ACHIEVEMENTS = defs.achievements;

export async function playerStats(tx: Tx, playerId: string) {
  const [campaign, perfectRows, endless, dailies] = await Promise.all([
    tx.playerLevelProgress.count({ where: { playerId, kind: 'campaign' } }),
    tx.$queryRaw<{ n: bigint }[]>`SELECT count(*)::bigint AS n FROM player_level_progress WHERE player_id = ${playerId}::uuid AND best_rotations <= par`,
    tx.playerLevelProgress.count({ where: { playerId, kind: 'endless', verified: true } }),
    tx.challengeSubmission.findMany({ where: { playerId, valid: true }, distinct: ['challengeId'], select: { challengeId: true } }),
  ]);
  return { campaign, perfect: Number(perfectRows[0]?.n ?? 0), endless, dailies: dailies.length };
}

/** Grant any newly reached achievements; returns their ids. Idempotent. */
export async function evaluateAchievements(tx: Tx, playerId: string): Promise<string[]> {
  const stats = await playerStats(tx, playerId);
  const have = new Set((await tx.playerAchievement.findMany({ where: { playerId }, select: { achievementId: true } })).map((a) => a.achievementId));
  const fresh = ACHIEVEMENTS.filter((a) => !have.has(a.id) && (stats[a.metric as keyof typeof stats] ?? 0) >= a.threshold).map((a) => a.id);
  if (fresh.length) await tx.playerAchievement.createMany({ data: fresh.map((achievementId) => ({ playerId, achievementId })), skipDuplicates: true });
  return fresh;
}
