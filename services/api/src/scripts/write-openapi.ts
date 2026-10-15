/** Writes docs/api/openapi.json from the route registry. `npm run openapi -w @loopfactory/api [-- --check]` */
import { readFileSync, writeFileSync, mkdirSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { API_VERSION } from '../app';
import { loadConfig } from '../config';
import { createDb } from '../db';
import { buildOpenApi } from '../openapi';
import { buildRoutes } from '../routes';
import { createIdentityVerifier } from '../services/identity';
import { createPurchaseVerifier } from '../services/purchases';
import { TokenService } from '../services/tokens';

const config = loadConfig({ ...process.env, DATABASE_URL: process.env.DATABASE_URL ?? 'postgresql://x@localhost/x', JWT_SECRET: process.env.JWT_SECRET ?? 'x'.repeat(32), DAILY_SEED_SECRET: process.env.DAILY_SEED_SECRET ?? 'x'.repeat(16), PRIVACY_HASH_SALT: process.env.PRIVACY_HASH_SALT ?? 'x'.repeat(16) });
const db = createDb(config.databaseUrl);
const routes = buildRoutes({ db, config, tokens: new TokenService(db, config.jwtSecret, 900, 90), identity: createIdentityVerifier(config), purchases: createPurchaseVerifier(config) });
const out = resolve(dirname(fileURLToPath(import.meta.url)), '../../../../docs/api/openapi.json');
const json = JSON.stringify(buildOpenApi(routes, API_VERSION), null, 2) + '\n';
if (process.argv.includes('--check')) {
  const cur = (() => { try { return readFileSync(out, 'utf8'); } catch { return ''; } })();
  if (cur !== json) {
    console.error('docs/api/openapi.json is stale; run npm run openapi -w @loopfactory/api');
    process.exit(1);
  }
  console.log('OpenAPI document up to date.');
} else {
  mkdirSync(dirname(out), { recursive: true });
  writeFileSync(out, json);
  console.log(`Wrote ${out} (${routes.length} operations)`);
}
await db.$disconnect();
