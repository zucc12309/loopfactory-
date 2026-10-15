import { defineConfig } from 'vitest/config';
export default defineConfig({
  test: {
    include: ['test/**/*.test.ts'],
    fileParallelism: false,
    testTimeout: 30_000,
    hookTimeout: 60_000,
    env: {
      NODE_ENV: 'test',
      DATABASE_URL: process.env.TEST_DATABASE_URL ?? 'postgresql://loop:loop@localhost:5432/loopfactory_test',
      JWT_SECRET: 'test-secret-test-secret-test-secret-123',
      DAILY_SEED_SECRET: 'test-daily-seed-secret',
      PRIVACY_HASH_SALT: 'test-privacy-salt-123',
      ENABLE_DEV_AUTH: 'true',
      ENABLE_DEV_PURCHASES: 'true',
      LOG_LEVEL: 'silent',
    },
  },
});
