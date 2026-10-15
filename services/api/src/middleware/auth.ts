import type { RequestHandler } from 'express';
import { ApiError } from '../errors';
import type { TokenService } from '../services/tokens';

function bearer(header: string | undefined): string | null {
  if (!header) return null;
  const m = /^Bearer\s+(.+)$/i.exec(header);
  return m ? (m[1] ?? null) : null;
}

export function authMiddleware(tokens: TokenService) {
  const required: RequestHandler = async (req, res, next) => {
    try {
      const t = bearer(req.headers.authorization);
      if (!t) throw new ApiError(401, 'unauthorized', 'Missing bearer token');
      res.locals.playerId = await tokens.verifyAccess(t);
      next();
    } catch (e) {
      next(e);
    }
  };
  const optional: RequestHandler = async (req, res, next) => {
    const t = bearer(req.headers.authorization);
    if (t) {
      try {
        res.locals.playerId = await tokens.verifyAccess(t);
      } catch {
        /* anonymous */
      }
    }
    next();
  };
  return { required, optional };
}
