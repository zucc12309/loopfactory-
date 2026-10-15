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
  async issue(playerId: string, familyId: string = randomUUID()) {
    const refreshToken = randomBytes(32).toString('base64url');
    await this.db.refreshToken.create({
      data: { playerId, familyId, tokenHash: sha256(refreshToken), expiresAt: new Date(Date.now() + this.refreshTtlDays * 86400_000) },
    });
    return { accessToken: await this.signAccess(playerId), accessTokenExpiresIn: this.accessTtl, refreshToken };
  }

  /**
   * Rotate a refresh token. Each token is single-use: presenting an already-rotated or revoked token
   * is treated as theft and revokes the whole token family (all sessions descended from that login).
   */
  async rotate(refreshToken: string) {
    const row = await this.db.refreshToken.findUnique({ where: { tokenHash: sha256(refreshToken) } });
    if (!row) throw new ApiError(401, 'invalid_refresh_token', 'Refresh token not recognised');
    if (row.revokedAt || row.rotatedAt) {
      await this.revokeFamily(row.familyId);
      throw new ApiError(401, 'refresh_token_reused', 'Refresh token was already used; session revoked');
    }
    if (row.expiresAt.getTime() < Date.now()) throw new ApiError(401, 'refresh_token_expired', 'Refresh token expired');
    // Conditional update guards against two concurrent rotations of the same token.
    const claimed = await this.db.refreshToken.updateMany({ where: { id: row.id, rotatedAt: null, revokedAt: null }, data: { rotatedAt: new Date() } });
    if (claimed.count !== 1) {
      await this.revokeFamily(row.familyId);
      throw new ApiError(401, 'refresh_token_reused', 'Refresh token was already used; session revoked');
    }
    const player = await this.db.player.findUnique({ where: { id: row.playerId }, select: { id: true } });
    if (!player) throw new ApiError(401, 'invalid_refresh_token', 'Account no longer exists');
    return { playerId: row.playerId, tokens: await this.issue(row.playerId, row.familyId) };
  }

  async revokeFamily(familyId: string) {
    await this.db.refreshToken.updateMany({ where: { familyId, revokedAt: null }, data: { revokedAt: new Date() } });
  }

  async revokeByToken(refreshToken: string, playerId: string) {
    const row = await this.db.refreshToken.findUnique({ where: { tokenHash: sha256(refreshToken) } });
    if (row && row.playerId === playerId) await this.revokeFamily(row.familyId);
  }
}
