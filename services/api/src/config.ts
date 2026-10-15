import { z } from 'zod';

const Env = z.object({
  NODE_ENV: z.enum(['development', 'test', 'production']).default('development'),
  PORT: z.coerce.number().int().default(8080),
  DATABASE_URL: z.string().min(1),
  JWT_SECRET: z.string().min(32, 'JWT_SECRET must be at least 32 characters'),
  DAILY_SEED_SECRET: z.string().min(16),
  PRIVACY_HASH_SALT: z.string().min(16),
  LOG_LEVEL: z.enum(['fatal', 'error', 'warn', 'info', 'debug', 'trace', 'silent']).default('info'),
  CORS_ORIGINS: z.string().default(''),
  GOOGLE_CLIENT_IDS: z.string().default(''),
  APPLE_BUNDLE_IDS: z.string().default(''),
  SENTRY_DSN: z.string().default(''),
  ENABLE_DEV_AUTH: z.enum(['true', 'false']).default('false'),
  ENABLE_DEV_PURCHASES: z.enum(['true', 'false']).default('false'),
  TRUST_PROXY: z.coerce.number().int().default(1),
  ACCESS_TOKEN_TTL_SECONDS: z.coerce.number().int().default(900),
  REFRESH_TOKEN_TTL_DAYS: z.coerce.number().int().default(90),
  RATE_LIMIT_DISABLED: z.enum(['true', 'false']).default('false'),
  /** Public origin used in friend-challenge links, e.g. https://play.loopfactory.example (no trailing slash). */
  PUBLIC_BASE_URL: z.string().url().or(z.literal('')).default(''),
  /** Optional store links shown on the challenge landing page. */
  PLAY_STORE_URL: z.string().url().or(z.literal('')).default(''),
  APP_STORE_URL: z.string().url().or(z.literal('')).default(''),
});

export type Config = ReturnType<typeof loadConfig>;

const PLACEHOLDER = /change-me/i;

export function loadConfig(env: NodeJS.ProcessEnv = process.env) {
  const parsed = Env.safeParse(env);
  if (!parsed.success) {
    throw new Error(`Invalid environment: ${parsed.error.issues.map((i) => `${i.path.join('.')}: ${i.message}`).join('; ')}`);
  }
  const c = parsed.data;
  if (c.NODE_ENV === 'production') {
    for (const key of ['JWT_SECRET', 'DAILY_SEED_SECRET', 'PRIVACY_HASH_SALT'] as const) {
      if (PLACEHOLDER.test(c[key])) throw new Error(`${key} still has a placeholder value in production`);
    }
    if (c.ENABLE_DEV_AUTH === 'true' || c.ENABLE_DEV_PURCHASES === 'true') {
      throw new Error('Dev auth/purchase providers must be disabled in production');
    }
  }
  const list = (s: string) => s.split(',').map((x) => x.trim()).filter(Boolean);
  return {
    env: c.NODE_ENV,
    port: c.PORT,
    databaseUrl: c.DATABASE_URL,
    jwtSecret: c.JWT_SECRET,
    dailySeedSecret: c.DAILY_SEED_SECRET,
    privacySalt: c.PRIVACY_HASH_SALT,
    logLevel: c.LOG_LEVEL,
    corsOrigins: list(c.CORS_ORIGINS),
    googleClientIds: list(c.GOOGLE_CLIENT_IDS),
    appleBundleIds: list(c.APPLE_BUNDLE_IDS),
    sentryDsn: c.SENTRY_DSN,
    devAuth: c.ENABLE_DEV_AUTH === 'true',
    devPurchases: c.ENABLE_DEV_PURCHASES === 'true',
    trustProxy: c.TRUST_PROXY,
    accessTtl: c.ACCESS_TOKEN_TTL_SECONDS,
    refreshTtlDays: c.REFRESH_TOKEN_TTL_DAYS,
    rateLimitDisabled: c.RATE_LIMIT_DISABLED === 'true',
    publicBaseUrl: c.PUBLIC_BASE_URL.replace(/\/$/, ''),
    playStoreUrl: c.PLAY_STORE_URL,
    appStoreUrl: c.APP_STORE_URL,
  };
}
