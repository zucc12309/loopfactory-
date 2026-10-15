import { verifyReplay, type Level } from '@loopfactory/engine';
import type { TSnapshot, TSyncOperation } from '@loopfactory/contracts';
import { Prisma } from '@prisma/client';
import type { Db } from '../db';
import { isUniqueViolation } from '../db';
import { evaluateAchievements, playerStats } from './achievements';
import { recomputeGlobal } from './leaderboards';
import type { LevelService } from './levels';

type Tx = Prisma.TransactionClient;
type OpResult = { opId: string; status: 'applied' | 'duplicate' | 'rejected'; error?: string };

/**
 * Offline-first synchronisation (docs/sync.md).
 *  - Each operation carries a client-generated opId; (player, opId) is unique, so retries are
 *    idempotent: a replayed op returns its original result without being applied twice.
 *  - Each op is applied in its own transaction together with its sync_operations record.
 *  - Conflict domains:
 *      completions   monotonic — a level once completed stays completed; best = min(best, new)
 *      settings      last-writer-wins on the client's updatedAt
 *      active puzzle last-writer-wins on the client's updatedAt
 *  - Completions with a replay are re-simulated and marked verified; only verified results count
 *    for leaderboards. Completions without a replay are kept (never lose progress) but unverified,
 *    and their claimed rotations are clamped to at least par.
 */
export class ProgressService {
  constructor(
    private db: Db,
    private levels: LevelService,
  ) {}

  async sync(playerId: string, ops: TSyncOperation[]): Promise<OpResult[]> {
    const results: OpResult[] = [];
    for (const op of ops) results.push(await this.applyOne(playerId, op));
    return results;
  }

  private async applyOne(playerId: string, op: TSyncOperation): Promise<OpResult> {
    const prior = await this.db.syncOperation.findUnique({ where: { playerId_opId: { playerId, opId: op.opId } } });
    if (prior) return prior.status === 'rejected' ? { opId: op.opId, status: 'duplicate', error: String((prior.result as { error?: string }).error ?? '') } : { opId: op.opId, status: 'duplicate' };
    // Validate/verify outside the transaction (CPU work), then write atomically.
    let rejection: string | null = null;
    let completion: { level: Level; verified: boolean; best: number; key: string } | null = null;
    if (op.type === 'level_complete') {
      const r = await this.prepareCompletion(op.payload);
      if ('error' in r) rejection = r.error;
      else completion = r;
    }
    try {
      await this.db.$transaction(async (tx) => {
        await tx.syncOperation.create({
          data: { playerId, opId: op.opId, type: op.type, status: rejection ? 'rejected' : 'applied', result: rejection ? { error: rejection } : {}, clientTs: BigInt(op.clientTs) },
        });
        if (rejection) return;
        switch (op.type) {
          case 'level_complete':
            await this.recordCompletion(tx, playerId, op.payload, completion!);
            break;
          case 'settings':
            await tx.player.updateMany({
              where: { id: playerId, settingsUpdatedAt: { lt: BigInt(op.payload.updatedAt) } },
              data: { settings: op.payload.settings as Prisma.InputJsonValue, settingsUpdatedAt: BigInt(op.payload.updatedAt) },
            });
            break;
          case 'active_puzzle': {
            const p = op.payload;
            const cur = await tx.activePuzzleState.findUnique({ where: { playerId } });
            if (!cur || cur.clientUpdatedAt < BigInt(p.updatedAt)) {
              await tx.activePuzzleState.upsert({
                where: { playerId },
                create: { playerId, kind: p.kind, levelKey: p.levelId, state: p as unknown as Prisma.InputJsonValue, clientUpdatedAt: BigInt(p.updatedAt) },
                update: { kind: p.kind, levelKey: p.levelId, state: p as unknown as Prisma.InputJsonValue, clientUpdatedAt: BigInt(p.updatedAt) },
              });
            }
            break;
          }
        }
      });
    } catch (e) {
      if (isUniqueViolation(e)) return { opId: op.opId, status: 'duplicate' }; // concurrent retry won the race
      throw e;
    }
    return rejection ? { opId: op.opId, status: 'rejected', error: rejection } : { opId: op.opId, status: 'applied' };
  }

  private async prepareCompletion(p: Extract<TSyncOperation, { type: 'level_complete' }>['payload']): Promise<{ error: string } | { level: Level; verified: boolean; best: number; key: string }> {
    let level: Level | null = null;
    let key = p.levelId;
    if (p.kind === 'campaign') {
      const found = await this.levels.get(p.levelId);
      if (!found) return { error: 'unknown_level' };
      if (found.version !== p.contentVersion && p.moves) return { error: 'stale_content_version' };
      level = found.level;
    } else {
      if (!p.generator || !p.moves) return { error: 'endless_requires_replay' };
      level = this.levels.endless(p.generator);
      if (!level) return { error: 'unsupported_generator' };
      key = `${p.generator.tier}-${p.generator.seed}`;
    }
    if (p.moves) {
      const v = verifyReplay(level, p.moves);
      if (!v.valid) return { error: `replay_${v.error}` };
      return { level, verified: true, best: v.rotations, key };
    }
    return { level, verified: false, best: Math.max(p.rotations, level.par), key };
  }

  private async recordCompletion(tx: Tx, playerId: string, p: Extract<TSyncOperation, { type: 'level_complete' }>['payload'], c: { level: Level; verified: boolean; best: number; key: string }) {
    const cur = await tx.playerLevelProgress.findUnique({ where: { playerId_kind_levelKey: { playerId, kind: p.kind, levelKey: c.key } } });
    if (!cur) {
      await tx.playerLevelProgress.create({
        data: {
          playerId, kind: p.kind, levelKey: c.key, contentVersion: p.contentVersion, generator: p.generator ?? Prisma.JsonNull,
          bestRotations: c.best, par: c.level.par, verified: c.verified, hintsUsed: p.hints, clientCompletedAt: BigInt(p.completedAt),
        },
      });
    } else {
      // A verified result always replaces an unverified one; otherwise keep the minimum.
      const better = c.verified && !cur.verified ? true : c.best < cur.bestRotations && (c.verified || !cur.verified);
      await tx.playerLevelProgress.update({
        where: { id: cur.id },
        data: {
          completions: { increment: 1 },
          lastCompletedAt: new Date(),
          hintsUsed: { increment: p.hints },
          ...(better ? { bestRotations: c.best, verified: c.verified || cur.verified } : {}),
        },
      });
    }
    if (p.kind === 'campaign' && c.verified) await recomputeGlobal(tx, playerId);
    await evaluateAchievements(tx, playerId);
  }

  async snapshot(playerId: string): Promise<TSnapshot> {
    const [player, progress, active, achievements, stats] = await Promise.all([
      this.db.player.findUnique({ where: { id: playerId }, select: { settings: true, settingsUpdatedAt: true } }),
      this.db.playerLevelProgress.findMany({ where: { playerId }, orderBy: { firstCompletedAt: 'asc' } }),
      this.db.activePuzzleState.findUnique({ where: { playerId } }),
      this.db.playerAchievement.findMany({ where: { playerId }, select: { achievementId: true } }),
      playerStats(this.db, playerId),
    ]);
    const settingsUpdatedAt = Number(player?.settingsUpdatedAt ?? 0);
    return {
      progress: progress.map((p) => ({
        levelId: p.levelKey, kind: p.kind, bestRotations: p.bestRotations, par: p.par, verified: p.verified,
        completedAt: Number(p.clientCompletedAt ?? BigInt(p.firstCompletedAt.getTime())),
      })),
      settings: settingsUpdatedAt > 0 ? { ...(player?.settings as object), updatedAt: settingsUpdatedAt } : null,
      activePuzzle: active ? (active.state as unknown as TSnapshot['activePuzzle']) : null,
      stats,
      achievements: achievements.map((a) => a.achievementId),
      serverTime: Date.now(),
    };
  }
}
