import type { NextFunction, Request, Response, RequestHandler, Router } from 'express';
import type { ZodTypeAny, z } from 'zod';
import { ApiError } from './errors';

/**
 * Route registry: every endpoint is declared once with its schemas. The same declaration
 * (1) validates params/query/body, (2) types the handler, and (3) feeds the OpenAPI document.
 */
export interface RouteDef<B extends ZodTypeAny | undefined, Q extends ZodTypeAny | undefined, R extends ZodTypeAny> {
  method: 'get' | 'post' | 'patch' | 'delete';
  path: string; // express style, e.g. /levels/:id
  summary: string;
  tag: string;
  auth: 'required' | 'optional' | 'none';
  body?: B;
  query?: Q;
  params?: Record<string, string>;
  response: R;
  status?: number;
  rateLimit?: RequestHandler;
  handler: (ctx: {
    req: Request;
    res: Response;
    body: B extends ZodTypeAny ? z.infer<B> : undefined;
    query: Q extends ZodTypeAny ? z.infer<Q> : undefined;
    playerId: string | null;
  }) => Promise<z.infer<R> | undefined>;
}

export type AnyRoute = RouteDef<ZodTypeAny | undefined, ZodTypeAny | undefined, ZodTypeAny>;
export const registry: AnyRoute[] = [];

export function defineRoute<B extends ZodTypeAny | undefined, Q extends ZodTypeAny | undefined, R extends ZodTypeAny>(def: RouteDef<B, Q, R>): AnyRoute {
  return def as unknown as AnyRoute;
}

export function mount(router: Router, routes: AnyRoute[], auth: { required: RequestHandler; optional: RequestHandler }): void {
  for (const r of routes) {
    registry.push(r);
    const chain: RequestHandler[] = [];
    if (r.auth === 'required') chain.push(auth.required);
    if (r.auth === 'optional') chain.push(auth.optional);
    if (r.rateLimit) chain.push(r.rateLimit);
    chain.push(async (req: Request, res: Response, next: NextFunction) => {
      try {
        const body = r.body ? r.body.parse(req.body ?? {}) : undefined;
        const query = r.query ? r.query.parse(req.query) : undefined;
        const out = await r.handler({ req, res, body, query, playerId: (res.locals.playerId as string | undefined) ?? null });
        if (res.headersSent) return;
        if (out === undefined) {
          res.status(r.status ?? 204).end();
          return;
        }
        res.status(r.status ?? 200).json(out);
      } catch (e) {
        next(e);
      }
    });
    router[r.method](r.path, ...chain);
  }
}

export function requirePlayer(playerId: string | null): string {
  if (!playerId) throw new ApiError(401, 'unauthorized', 'Authentication required');
  return playerId;
}
