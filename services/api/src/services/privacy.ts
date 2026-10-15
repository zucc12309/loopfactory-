import { createHash } from 'node:crypto';
import type { Db } from '../db';

/** Data-subject requests: export (machine-readable JSON) and erasure (hard delete, cascading). */
export class PrivacyService {
  constructor(
    private db: Db,
    private salt: string,
  ) {}

  subjectHash(playerId: string) {
    return createHash('sha256').update(`${this.salt}:${playerId}`).digest('hex');
  }

  async export(playerId: string) {
    const player = await this.db.player.findUnique({
      where: { id: playerId },
      include: {
        identities: { select: { provider: true, createdAt: true } },
        progress: true,
        activePuzzle: true,
        submissions: { select: { createdAt: true, rotations: true, valid: true, challenge: { select: { date: true } } } },
        leaderboard: { select: { board: true, score: true, achievedAt: true } },
        achievements: true,
        entitlements: { select: { store: true, productId: true, status: true, verifiedAt: true } },
        friendChallenges: { select: { code: true, levelRef: true, creatorRotations: true, createdAt: true, expiresAt: true } },
        friendAttempts: { select: { rotations: true, tries: true, updatedAt: true, challenge: { select: { code: true } } } },
      },
    });
    await this.db.privacyRequest.create({ data: { subjectHash: this.subjectHash(playerId), type: 'export', status: 'completed', completedAt: new Date() } });
    return JSON.parse(JSON.stringify({ exportedAt: new Date().toISOString(), player }, (_k, v) => (typeof v === 'bigint' ? Number(v) : v)));
  }

  /** Irreversibly deletes the account and everything linked to it (FK cascades). */
  async erase(playerId: string) {
    return this.db.$transaction(async (tx) => {
      const req = await tx.privacyRequest.create({ data: { subjectHash: this.subjectHash(playerId), type: 'delete', status: 'completed', completedAt: new Date() } });
      await tx.player.deleteMany({ where: { id: playerId } });
      return req.id;
    });
  }
}
