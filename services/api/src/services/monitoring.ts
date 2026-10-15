/**
 * Error-monitoring adapter. The default reporter only logs. When SENTRY_DSN is set and the optional
 * `@sentry/node` package is installed, errors are forwarded to Sentry. (The package is intentionally
 * not a hard dependency; see docs/operations.md.)
 */
export interface ErrorReporter {
  capture(err: unknown, context?: Record<string, unknown>): void;
}

export const noopReporter: ErrorReporter = { capture: () => {} };

export async function createReporter(dsn: string, environment: string): Promise<ErrorReporter> {
  if (!dsn) return noopReporter;
  try {
    const Sentry = (await import(/* @vite-ignore */ '@sentry/node' as string)) as {
      init: (o: object) => void;
      captureException: (e: unknown, o?: object) => void;
    };
    Sentry.init({ dsn, environment, sendDefaultPii: false, tracesSampleRate: 0 });
    return { capture: (err, context) => Sentry.captureException(err, { extra: context }) };
  } catch {
    console.warn('SENTRY_DSN set but @sentry/node is not installed; error reporting disabled');
    return noopReporter;
  }
}
