import type { Request, RequestHandler } from 'express';
import rateLimit from 'express-rate-limit';

/**
 * In-memory rate limiting (per instance). For multi-instance deployments, plug a shared store
 * (e.g. rate-limit-redis) into `store` — documented in docs/operations.md. Authenticated limits key
 * on the player id so players behind shared mobile-carrier NAT are not throttled together.
 */
export function makeLimiter(opts: { windowMs: number; limit: number; byPlayer?: boolean; disabled: boolean; name: string }): RequestHandler {
  if (opts.disabled) return (_req, _res, next) => next();
  return rateLimit({
    windowMs: opts.windowMs,
    limit: opts.limit,
    standardHeaders: 'draft-7',
    legacyHeaders: false,
    keyGenerator: (req: Request, res) => (opts.byPlayer && res.locals.playerId ? `p:${res.locals.playerId}` : `ip:${req.ip}`),
    handler: (_req, res) => {
      res.status(429).json({ error: { code: 'rate_limited', message: `Too many requests (${opts.name}); slow down` } });
    },
  });
}
