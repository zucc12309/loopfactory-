import pino from 'pino';

/** Structured JSON logs. Secrets and personal data are redacted at the logger level. */
export function createLogger(level: string) {
  return pino({
    level,
    base: { service: 'loopfactory-api' },
    redact: {
      paths: [
        'req.headers.authorization',
        'req.headers.cookie',
        '*.refreshToken',
        '*.accessToken',
        '*.idToken',
        '*.purchaseToken',
        'body.refreshToken',
        'body.idToken',
      ],
      censor: '[redacted]',
    },
    timestamp: pino.stdTimeFunctions.isoTime,
  });
}
export type Logger = ReturnType<typeof createLogger>;
