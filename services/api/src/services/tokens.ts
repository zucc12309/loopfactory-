import { createHash, randomBytes, randomUUID } from 'node:crypto';
import { SignJWT, jwtVerify } from 'jose';
import type { Db } from '../db';
import { ApiError } from '../errors';

const ISSUER = 'loopfactory';
const AUDIENCE = 'loopfactory-client';

export const sha256 = (s: string) => createHash('sha256').update(s).digest('hex');

export class TokenService {
  private key: Uint8Array;
  constructor(
    private db: Db,
    secret: string,
    private accessTtl: number,
    private refreshTtlDays: number,
    private reuseGraceSeconds = 0,
  ) {
    this.key = new TextEncoder().encode(secret);
  }

  async signAccess(playerId: string): Promise<string> {
    return new SignJWT({})
      .setProtectedHeader({ alg: 'HS256', typ: 'JWT' })
      .setSubject(playerId)
      .setIssuer(ISSUER)
      .setAudience(AUDIENCE)
      .setIssuedAt()
      .setJti(randomUUID())
      .setExpirationTime(`${this.accessTtl}s`)
      .sign(this.key);
  }

  async verifyAccess(token: string): Promise<string> {
    try {
      const { payload } = await jwtVerify(token, this.key, { issuer: ISSUER, audience: AUDIENCE, algorithms: ['HS256'] });
      if (!payload.sub) throw new Error('no subject');
      return payload.sub;
    } catch {
      throw new ApiError(401, 'invalid_token', 'Access token is invalid or expired');
    }
  }

  /** Issue a new refresh token (opaque, 256-bit) — only its SHA-256 hash is stored. */
  async issue(playerId: string, familyId: string = randomUUID(), db: Pick<Db, 'refreshToken'> = this.db) {
    const refreshToken = randomBytes(32).toString('base64url');
    const row = await db.refreshToken.create({
      data: { playerId, familyId, tokenHash: sha256(refreshToken), expiresAt: new Date(Date.now() + this.refreshTtlDays * 86400_000) },
    });
    return { id: row.id, tokens: { accessToken: await this.signAccess(playerId), accessTokenExpiresIn: this.accessTtl, refreshToken } };
  }

  /** Public form of issue(): just the credentials. */
  async issueTokens(playerId: string) {
    return (await this.issue(playerId)).tokens;
  }

  /**
   * Rotate a refresh token. Each token is single-use: presenting an already-rotated or revoked token
   * is treated as theft and revokes the whole token family (all sessions descended from that login).
   *
   * One bounded exception covers a lost response (the server rotated, the client never received the
   * successor, e.g. a dropped connection or the app being killed): if the token is presented again
   * within `reuseGraceSeconds` of its rotation AND its successor has never been used, the unused
   * successor is revoked and a fresh one is issued. Only one live successor ever exists, so an
   * attacker replaying a stolen token inside the window invalidates the victim's token, and the
   * victim's next refresh then trips reuse detection and revokes the family (theft still surfaces).
   */
  async rotate(refreshToken: string) {
    const row = await this.db.refreshToken.findUnique({ where: { tokenHash: sha256(refreshToken) } });
    if (!row) throw new ApiError(401, 'invalid_refresh_token', 'Refresh token not recognised');
    if (row.revokedAt) {
      await this.revokeFamily(row.familyId);
      throw new ApiError(401, 'refresh_token_reused', 'Refresh token was already used; session revoked');
    }
    if (row.expiresAt.getTime() < Date.now()) throw new ApiError(401, 'refresh_token_expired', 'Refresh token expired');
    const player = await this.db.player.findUnique({ where: { id: row.playerId }, select: { id: true } });
    if (!player) throw new ApiError(401, 'invalid_refresh_token', 'Account no longer exists');
    if (!row.rotatedAt) {
      // Claim + successor + link commit together, so a concurrent caller either wins the claim or
      // sees the finished rotation (never a half-rotated token).
      const won = await this.db.$transaction(async (tx) => {
        const claimed = await tx.refreshToken.updateMany({ where: { id: row.id, rotatedAt: null, revokedAt: null }, data: { rotatedAt: new Date() } });
        if (claimed.count !== 1) return null;
        const next = await this.issue(row.playerId, row.familyId, tx);
        await tx.refreshToken.update({ where: { id: row.id }, data: { replacedById: next.id } });
        return next.tokens;
      });
      if (won) return { playerId: row.playerId, tokens: won, recovered: false };
    }
    const recovered = await this.retryAfterLostResponse(row.id);
    if (recovered) return { playerId: row.playerId, tokens: recovered, recovered: true };
    await this.revokeFamily(row.familyId);
    throw new ApiError(401, 'refresh_token_reused', 'Refresh token was already used; session revoked');
  }

  private async retryAfterLostResponse(id: string) {
    if (this.reuseGraceSeconds <= 0) return null;
    return this.db.$transaction(async (tx) => {
      // Row lock: concurrent retries of the same token queue here and each sees the latest successor.
      await tx.$queryRaw`SELECT id FROM refresh_tokens WHERE id = ${id}::uuid FOR UPDATE`;
      const cur = await tx.refreshToken.findUnique({ where: { id } });
      if (!cur || cur.revokedAt || !cur.rotatedAt || !cur.replacedById) return null;
      if (Date.now() - cur.rotatedAt.getTime() > this.reuseGraceSeconds * 1000) return null;
      // The successor must be untouched; revoking it conditionally makes concurrent retries serialise.
      const dropped = await tx.refreshToken.updateMany({ where: { id: cur.replacedById, rotatedAt: null, revokedAt: null }, data: { revokedAt: new Date() } });
      if (dropped.count !== 1) return null;
      const next = await this.issue(cur.playerId, cur.familyId, tx);
      await tx.refreshToken.update({ where: { id }, data: { replacedById: next.id } });
      return next.tokens;
    });
  }

  async revokeFamily(familyId: string) {
    await this.db.refreshToken.updateMany({ where: { familyId, revokedAt: null }, data: { revokedAt: new Date() } });
  }

  async revokeByToken(refreshToken: string, playerId: string) {
    const row = await this.db.refreshToken.findUnique({ where: { tokenHash: sha256(refreshToken) } });
    if (row && row.playerId === playerId) await this.revokeFamily(row.familyId);
  }
}
