import cluster from 'node:cluster';
import { availableParallelism } from 'node:os';
import { createApp } from './app';
import { loadConfig } from './config';
import { createDb } from './db';
import { createLogger } from './logger';
import { createReporter } from './services/monitoring';

const config = loadConfig();
const logger = createLogger(config.logLevel);
// WEB_CONCURRENCY > 1 forks that many worker processes sharing the port (use ≈ vCPUs).
// Note: rate limits are in-memory per worker; DB_POOL_SIZE applies per worker.
const workers = Math.min(Number(process.env.WEB_CONCURRENCY ?? 1), availableParallelism());

if (workers > 1 && cluster.isPrimary) {
  logger.info({ workers }, 'starting worker processes');
  for (let i = 0; i < workers; i++) cluster.fork();
  cluster.on('exit', (w, code, signal) => {
    if (!shuttingDown) {
      logger.error({ pid: w.process.pid, code, signal }, 'worker died; restarting');
      cluster.fork();
    }
  });
  let shuttingDown = false;
  const stop = () => {
    shuttingDown = true;
    for (const w of Object.values(cluster.workers ?? {})) w?.process.kill('SIGTERM');
    setTimeout(() => process.exit(0), 11_000).unref();
  };
  process.on('SIGTERM', stop);
  process.on('SIGINT', stop);
} else {
  const db = createDb(config.databaseUrl, Number(process.env.DB_POOL_SIZE ?? 10));
  const reporter = await createReporter(config.sentryDsn, config.env);
  const app = createApp({ config, db, logger, reporter });

  // Large accept backlog so connection bursts (daily-puzzle spikes) queue instead of being reset.
  const server = app.listen({ port: config.port, backlog: 4096 }, () => logger.info({ port: config.port, env: config.env, pid: process.pid }, 'Loop Factory API listening'));
  server.keepAliveTimeout = 65_000; // longer than typical load-balancer idle timeouts
  server.headersTimeout = 66_000;

  let closing = false;
  const shutdown = async (signal: string) => {
    if (closing) return;
    closing = true;
    logger.info({ signal }, 'shutting down');
    server.close(async () => {
      await db.$disconnect();
      process.exit(0);
    });
    setTimeout(() => process.exit(1), 10_000).unref();
  };
  process.on('SIGTERM', () => void shutdown('SIGTERM'));
  process.on('SIGINT', () => void shutdown('SIGINT'));
  process.on('unhandledRejection', (err) => {
    logger.error({ err }, 'unhandled rejection');
    reporter.capture(err);
  });
}
