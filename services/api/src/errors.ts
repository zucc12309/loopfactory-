import type { ErrorRequestHandler, RequestHandler } from 'express';
import { ZodError } from 'zod';
import type { Logger } from './logger';
import type { ErrorReporter } from './services/monitoring';

export class ApiError extends Error {
  constructor(
    public status: number,
    public code: string,
    message: string,
    public details?: unknown,
  ) {
    super(message);
  }
}

export const notFound: RequestHandler = (req, _res, next) => next(new ApiError(404, 'not_found', `No route for ${req.method} ${req.path}`));

/** Single error funnel: consistent JSON shape, no stack traces or internals leaked to clients. */
export function errorHandler(logger: Logger, reporter: ErrorReporter): ErrorRequestHandler {
  return (err, req, res, _next) => {
    const requestId = String(res.getHeader('x-request-id') ?? '');
    if (err instanceof ZodError) {
      res.status(400).json({ error: { code: 'validation_error', message: 'Request validation failed', requestId, details: err.issues.map((i) => ({ path: i.path.join('.'), message: i.message })) } });
      return;
    }
    if (err instanceof ApiError) {
      res.status(err.status).json({ error: { code: err.code, message: err.message, requestId, details: err.details } });
      return;
    }
    if (err?.type === 'entity.parse.failed') {
      res.status(400).json({ error: { code: 'invalid_json', message: 'Malformed JSON body', requestId } });
      return;
    }
    if (err?.type === 'entity.too.large') {
      res.status(413).json({ error: { code: 'payload_too_large', message: 'Request body too large', requestId } });
      return;
    }
    logger.error({ err, requestId, path: req.path }, 'unhandled error');
    reporter.capture(err, { requestId, path: req.path });
    res.status(500).json({ error: { code: 'internal_error', message: 'Something went wrong', requestId } });
  };
}
