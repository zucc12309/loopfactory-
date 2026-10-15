import { createApp } from './app';
import { loadConfig } from './config';
import { createDb } from './db';
import { createLogger } from './logger';
import { createReporter } from './services/monitoring';

const config = loadConfig();
const logger = createLogger(config.logLevel);
const db = createDb(config.databaseUrl, Number(process.env.DB_POOL_SIZE ?? 10));
const reporter = await createReporter(config.sentryDsn, config.env);
const app = createApp({ config, db, logger, reporter });

const server = app.listen(config.port, () => logger.info({ port: config.port, env: config.env }, 'Loop Factory API listening'));
server.keepAliveTimeout = 65_000; // longer than typical load-balancer idle timeouts

let closing = false;
async function shutdown(signal: string) {
  if (closing) return;
  closing = true;
  logger.info({ signal }, 'shutting down');
  server.close(async () => {
    await db.$disconnect();
    process.exit(0);
  });
  setTimeout(() => process.exit(1), 10_000).unref();
}
process.on('SIGTERM', () => void shutdown('SIGTERM'));
process.on('SIGINT', () => void shutdown('SIGINT'));
process.on('unhandledRejection', (err) => {
  logger.error({ err }, 'unhandled rejection');
  reporter.capture(err);
});
