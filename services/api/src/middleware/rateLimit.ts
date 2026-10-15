import type { NextFunction, Request, RequestHandler, Response } from 'express';
import rateLimit from 'express-rate-limit';
import { sha256, type TokenService } from '../services/tokens';

/**
 * Rate limiting (docs/security.md, "Rate limits").
 *
 * Keys: a request carrying a VALID access token is limited per player, so players who share a
 * mobile-carrier NAT IP never share a bucket. Anonymous requests are limited per client IP (as
 * resolved through TRUST_PROXY hops). Refresh calls are limited per refresh token.
 *
 * Storage: in process memory. Limits are therefore PER API INSTANCE and reset on restart; this is
 * correct for the single-instance beta topology. Running several instances multiplies the effective
 * limits by the instance count: plug a shared store (e.g. rate-limit-postgresql / Redis) into
 * `store` before scaling out. The startup log states this.
 */
export const RATE_LIMIT_STORE = 'memory-per-instance';

export type LimitKey = 'player' | 'ip' | 'player-or-ip' | 'refresh-token';

/** Best-effort identification for limiter keys only (never authorizes anything). */
export function identify(tokens: TokenService): RequestHandler {
  return async (req: Request, res: Response, next: NextFunction) => {
    const h = req.headers.authorization;
    if (typeof h === 'string' && h.startsWith('Bearer ')) {
      try {
        res.locals.rlPlayer = await tokens.verifyAccess(h.slice(7));
      } catch {
        /* invalid token: treated as anonymous; the auth middleware rejects it where required */
      }
    }
    next();
  };
}

export function limitKey(kind: LimitKey, req: Request, res: Response): string {
  const player = (res.locals.playerId as string | undefined) ?? (res.locals.rlPlayer as string | undefined);
  switch (kind) {
    case 'player':
    case 'player-or-ip':
      return player ? `p:${player}` : `ip:${req.ip}`;
    case 'refresh-token': {
      const t = (req.body as { refreshToken?: unknown } | undefined)?.refreshToken;
      return typeof t === 'string' && t.length > 0 ? `rt:${sha256(t).slice(0, 32)}` : `ip:${req.ip}`;
    }
    default:
      return `ip:${req.ip}`;
  }
}

export function makeLimiter(opts: { windowMs: number; limit: number; key?: LimitKey; byPlayer?: boolean; disabled: boolean; name: string }): RequestHandler {
  if (opts.disabled) return (_req, _res, next) => next();
  const kind: LimitKey = opts.key ?? (opts.byPlayer ? 'player' : 'ip');
  return rateLimit({
    windowMs: opts.windowMs,
    limit: opts.limit,
    standardHeaders: 'draft-7',
    legacyHeaders: false,
    keyGenerator: (req: Request, res) => limitKey(kind, req, res),
    handler: (_req, res) => {
      res.status(429).json({ error: { code: 'rate_limited', message: `Too many requests (${opts.name}); slow down` } });
    },
  });
}
