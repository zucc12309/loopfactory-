import type { Prisma } from '@prisma/client';
import type { Db } from '../db';

type Tx = Prisma.TransactionClient;

/**
 * Leaderboards share one table; on every board a LOWER score ranks higher and ties go to whoever
 * reached the score first (server time).
 *  - daily:YYYY-MM-DD  score = rotations of the best verified replay
 *  - weekly:YYYY-Www   score = -solved * 10000 + total rotations (more dailies solved first, then fewer rotations)
 *  - global            score = -verified campaign levels * 100000 + sum of best rotations
 * Only server-verified results (replays re-simulated by the engine) ever reach a leaderboard.
 */
export function isoWeek(date: Date): string {
  const d = new Date(Date.UTC(date.getUTCFullYear(), date.getUTCMonth(), date.getUTCDate()));
  const day = d.getUTCDay() || 7;
  d.setUTCDate(d.getUTCDate() + 4 - day);
  const yearStart = new Date(Date.UTC(d.getUTCFullYear(), 0, 1));
  const week = Math.ceil(((d.getTime() - yearStart.getTime()) / 86400000 + 1) / 7);
  return `${d.getUTCFullYear()}-W${String(week).padStart(2, '0')}`;
}

export function weekRange(week: string): { start: Date; end: Date } {
  const [y, w] = week.split('-W').map(Number) as [number, number];
  const jan4 = new Date(Date.UTC(y, 0, 4));
  const day = jan4.getUTCDay() || 7;
  const start = new Date(jan4.getTime() - (day - 1) * 86400000 + (w - 1) * 7 * 86400000);
  return { start, end: new Date(start.getTime() + 7 * 86400000) };
}

export async function upsertBest(tx: Tx, board: string, playerId: string, score: number, display: Record<string, number>) {
  const cur = await tx.leaderboardEntry.findUnique({ where: { board_playerId: { board, playerId } } });
  if (!cur) {
    await tx.leaderboardEntry.create({ data: { board, playerId, score, display } });
  } else if (score < cur.score) {
    await tx.leaderboardEntry.update({ where: { id: cur.id }, data: { score, display, achievedAt: new Date() } });
  }
}

export async function setScore(tx: Tx, board: string, playerId: string, score: number, display: Record<string, number>) {
  const cur = await tx.leaderboardEntry.findUnique({ where: { board_playerId: { board, playerId } } });
  if (!cur) await tx.leaderboardEntry.create({ data: { board, playerId, score, display } });
  else if (cur.score !== score) await tx.leaderboardEntry.update({ where: { id: cur.id }, data: { score, display, achievedAt: new Date() } });
}

export async function recomputeWeekly(tx: Tx, playerId: string, date: Date) {
  const week = isoWeek(date);
  const { start, end } = weekRange(week);
  const rows = await tx.$queryRaw<{ solved: bigint; rotations: bigint | null }[]>`
    SELECT count(*)::bigint AS solved, sum(best)::bigint AS rotations FROM (
      SELECT min(s.rotations) AS best FROM challenge_submissions s
      JOIN daily_challenges c ON c.id = s.challenge_id
      WHERE s.player_id = ${playerId}::uuid AND s.valid AND c.date >= ${start}::date AND c.date < ${end}::date
      GROUP BY s.challenge_id) t`;
  const solved = Number(rows[0]?.solved ?? 0);
  const rotations = Number(rows[0]?.rotations ?? 0);
  if (solved > 0) await setScore(tx, `weekly:${week}`, playerId, -solved * 10000 + rotations, { solved, rotations });
}

export async function recomputeGlobal(tx: Tx, playerId: string) {
  const rows = await tx.$queryRaw<{ solved: bigint; rotations: bigint | null }[]>`
    SELECT count(*)::bigint AS solved, sum(best_rotations)::bigint AS rotations FROM player_level_progress
    WHERE player_id = ${playerId}::uuid AND kind = 'campaign' AND verified`;
  const solved = Number(rows[0]?.solved ?? 0);
  const rotations = Number(rows[0]?.rotations ?? 0);
  if (solved > 0) await setScore(tx, 'global', playerId, -solved * 100000 + rotations, { solved, rotations });
}

export interface RankedEntry {
  rank: number;
  displayName: string;
  score: number;
  rotations: number;
  solved?: number;
  isMe: boolean;
}

export async function readBoard(db: Db, board: string, limit: number, me: string | null) {
  const rows = await db.leaderboardEntry.findMany({
    where: { board },
    orderBy: [{ score: 'asc' }, { achievedAt: 'asc' }, { playerId: 'asc' }],
    take: limit,
    include: { player: { select: { displayName: true } } },
  });
  const toEntry = (r: (typeof rows)[number], rank: number): RankedEntry => {
    const d = (r.display ?? {}) as { solved?: number; rotations?: number };
    const e: RankedEntry = { rank, displayName: r.player.displayName, score: board === 'global' || board.startsWith('weekly') ? (d.solved ?? 0) : r.score, rotations: d.rotations ?? r.score, isMe: r.playerId === me };
    if (d.solved !== undefined) e.solved = d.solved;
    return e;
  };
  const entries = rows.map((r, i) => toEntry(r, i + 1));
  let mine: RankedEntry | null = entries.find((e) => e.isMe) ?? null;
  if (!mine && me) {
    const row = await db.leaderboardEntry.findUnique({ where: { board_playerId: { board, playerId: me } }, include: { player: { select: { displayName: true } } } });
    if (row) {
      const better = await db.leaderboardEntry.count({ where: { board, OR: [{ score: { lt: row.score } }, { score: row.score, achievedAt: { lt: row.achievedAt } }] } });
      mine = toEntry(row, better + 1);
    }
  }
  return { board, entries, me: mine };
}
