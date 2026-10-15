import { randomUUID } from 'node:crypto';
import cors from 'cors';
import express from 'express';
import helmet from 'helmet';
import { pinoHttp } from 'pino-http';
import { API_PREFIX } from '@loopfactory/contracts';
import type { Config } from './config';
import type { Db } from './db';
import { errorHandler, notFound } from './errors';
import { mount, registry } from './http';
import type { Logger } from './logger';
import { authMiddleware } from './middleware/auth';
import { makeLimiter } from './middleware/rateLimit';
import { buildOpenApi } from './openapi';
import { buildRoutes } from './routes';
import { DailyService } from './services/daily';
import { FriendChallengeService, landingPage } from './services/friends';
import { createIdentityVerifier, type IdentityVerifier } from './services/identity';
import { LevelService } from './services/levels';
import { noopReporter, type ErrorReporter } from './services/monitoring';
import { createPurchaseVerifier, type PurchaseVerifier } from './services/purchases';
import { TokenService } from './services/tokens';

export const API_VERSION = '1.0.0';

export function createApp(opts: { config: Config; db: Db; logger: Logger; reporter?: ErrorReporter; identity?: IdentityVerifier; purchases?: PurchaseVerifier }) {
  const { config, db, logger } = opts;
  const app = express();
  app.disable('x-powered-by');
  app.set('trust proxy', config.trustProxy);
  app.use(helmet());
  app.use(cors({ origin: config.corsOrigins.length ? config.corsOrigins : false }));
  app.use((req, res, next) => {
    const incoming = req.headers['x-request-id'];
    const id = typeof incoming === 'string' && /^[\w-]{8,64}$/.test(incoming) ? incoming : randomUUID();
    res.setHeader('x-request-id', id);
    next();
  });
  app.use(
    pinoHttp({
      logger,
      genReqId: (_req, res) => String(res.getHeader('x-request-id')),
      autoLogging: { ignore: (req) => req.url === '/health' },
      serializers: { req: (req) => ({ id: req.id, method: req.method, url: req.url }), res: (res) => ({ statusCode: res.statusCode }) },
    }),
  );
  app.use(express.json({ limit: '256kb' }));
  app.use(makeLimiter({ name: 'global', windowMs: 60_000, limit: 600, disabled: config.rateLimitDisabled }));

  app.get('/health', (_req, res) => res.json({ status: 'ok', version: API_VERSION }));
  app.get('/ready', async (_req, res) => {
    try {
      await db.$queryRaw`SELECT 1`;
      res.json({ status: 'ready' });
    } catch {
      res.status(503).json({ status: 'unavailable' });
    }
  });

  const tokens = new TokenService(db, config.jwtSecret, config.accessTtl, config.refreshTtlDays, config.refreshReuseGraceSeconds);
  const routes = buildRoutes({
    db,
    config,
    tokens,
    identity: opts.identity ?? createIdentityVerifier(config),
    purchases: opts.purchases ?? createPurchaseVerifier(config),
  });
  const router = express.Router();
  registry.length = 0;
  mount(router, routes, authMiddleware(tokens));
  app.use(API_PREFIX, router);
  const doc = buildOpenApi(routes, API_VERSION);
  app.get('/openapi.json', (_req, res) => res.json(doc));

  // Challenge link landing page for people who don't have the app yet.
  const friends = new FriendChallengeService(db, new LevelService(db), new DailyService(db, config.dailySeedSecret), config.publicBaseUrl);
  app.get('/c/:code', async (req, res, next) => {
    try {
      const code = String(req.params.code).toUpperCase();
      let view = null;
      if (/^[A-HJ-NP-Z2-9]{8}$/.test(code)) {
        try {
          const v = await friends.view(code);
          view = { code: v.code, creatorName: v.creatorName, creatorRotations: v.creatorRotations, levelName: v.level.name, difficulty: v.level.difficulty, par: v.level.par };
        } catch {
          view = null;
        }
      }
      res.status(view ? 200 : 404).type('html').setHeader('Cache-Control', 'public, max-age=300');
      res.send(landingPage(view, { play: config.playStoreUrl, app: config.appStoreUrl }));
    } catch (e) {
      next(e);
    }
  });

  app.use(notFound);
  app.use(errorHandler(logger, opts.reporter ?? noopReporter));
  return app;
}
