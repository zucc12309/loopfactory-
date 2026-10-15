/**
 * Client configuration for builds (audit R1). The game reads res://config/client.json; this script
 * produces and checks it, so a release artifact can never ship a loopback API, a placeholder privacy
 * URL or a test switch.
 *
 *   tsx scripts/client-config.ts write <env> [--out apps/game/config/client.json]
 *       Builds client.json from config/client/<env>.json plus environment overrides
 *       (LF_API_BASE_URL, LF_PRIVACY_POLICY_URL, LF_SUPPORT_URL, LF_APP_LINK_HOST, LF_POSTHOG_KEY,
 *       LF_BUILD), validates it and writes it. Exits 1 (writing nothing) if invalid.
 *   tsx scripts/client-config.ts check <file>       Validate a client.json.
 *   tsx scripts/client-config.ts inspect <apk|aab> [expected.json]
 *       Extract the config packaged INSIDE an artifact, validate it and (optionally) require it to
 *       equal the expected file byte for byte.
 *   tsx scripts/client-config.ts selftest           Run the shared cases (apps/game/tests/fixtures/config-cases.json);
 *       LFReleaseConfig (GDScript) runs the same cases in the Godot suite.
 *
 * The rules mirror apps/game/scripts/core/release_config.gd — change both together.
 */
import { execFileSync } from 'node:child_process';
import { existsSync, readFileSync, writeFileSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
export const ENVIRONMENTS = ['development', 'staging', 'production'] as const;
const REQUIRED_URLS = ['apiBaseUrl', 'privacyPolicyUrl', 'supportUrl'] as const;
const TEST_ONLY_KEYS = ['devAuth', 'devPurchases', 'testMode', 'fakeServer'];
const SECRET_HINTS = ['secret', 'password', 'privatekey', 'serviceaccount', 'jwt'];

type Config = Record<string, unknown>;

export function urlProblem(u: string, release: boolean): string {
  const lower = u.trim().toLowerCase();
  const se = lower.indexOf('://');
  if (se < 0) return 'not an absolute URL';
  const scheme = lower.slice(0, se);
  let host = lower.slice(se + 3).split('/')[0]!.split('?')[0]!;
  if (host.includes('@')) return 'credentials in URL';
  if (!host.startsWith('[')) host = host.split(':')[0]!;
  if (!host) return 'missing host';
  const loopback = host === 'localhost' || host.startsWith('127.') || host === '[::1]' || host === '0.0.0.0' || host.endsWith('.localhost');
  const p172 = /^172\.(\d+)\./.exec(host);
  const priv = host.startsWith('10.') || host.startsWith('192.168.') || (p172 !== null && +p172[1]! >= 16 && +p172[1]! <= 31) || host.endsWith('.local') || host.endsWith('.internal');
  if (!release) return scheme === 'http' || scheme === 'https' ? '' : 'unsupported scheme';
  if (scheme !== 'https') return 'must use https';
  if (loopback) return 'loopback host';
  if (priv) return 'private/development host';
  if (host.endsWith('.example') || host.includes('.example.') || host === 'example.com' || host.endsWith('.example.com') || host.endsWith('.test') || host.endsWith('.invalid')) return 'placeholder domain';
  if (lower.includes('your-domain') || lower.includes('change-me') || lower.includes('placeholder')) return 'placeholder value';
  if (!host.includes('.')) return 'not a public host name';
  return '';
}

function scanSecrets(v: unknown, path: string, errs: string[]) {
  if (v && typeof v === 'object' && !Array.isArray(v)) {
    for (const [k, val] of Object.entries(v)) {
      const key = k.toLowerCase().replace(/[-_]/g, '');
      for (const h of SECRET_HINTS) if (key.includes(h) && String(val) !== '') errs.push(`secret-looking field '${path}${k}' must not ship in the client`);
      scanSecrets(val, `${path}${k}.`, errs);
    }
  }
}

export function validate(cfg: Config): string[] {
  const errs: string[] = [];
  const env = String(cfg.environment ?? '');
  if (!(ENVIRONMENTS as readonly string[]).includes(env)) return [`environment must be one of ${ENVIRONMENTS.join(', ')} (got '${env}')`];
  const release = env !== 'development';
  for (const key of REQUIRED_URLS) {
    const u = String(cfg[key] ?? '');
    if (!u) {
      if (release) errs.push(`${key} is required for ${env} builds`);
      continue;
    }
    const why = urlProblem(u, release);
    if (why) errs.push(`${key}: ${why} (${u})`);
  }
  const host = String((cfg.appLinks as Config | undefined)?.host ?? '');
  if (host) {
    const hp = urlProblem(`https://${host}`, release);
    if (hp) errs.push(`appLinks.host: ${hp}`);
  }
  if (release) {
    if (!(Number(cfg.build) > 0)) errs.push(`build must be a positive integer for ${env} builds`);
    for (const k of TEST_ONLY_KEYS) if (cfg[k] === true) errs.push(`test-only switch '${k}' is on`);
  }
  scanSecrets(cfg, '', errs);
  return errs;
}

function readJson(file: string): Config {
  return JSON.parse(readFileSync(file, 'utf8')) as Config;
}

export function build(env: string, overrides: NodeJS.ProcessEnv = process.env): Config {
  const base = readJson(resolve(root, `config/client/${env}.json`));
  const cfg: Config = { ...base, environment: env };
  const set = (k: string, v: string | undefined) => {
    if (v !== undefined && v !== '') cfg[k] = v;
  };
  set('apiBaseUrl', overrides.LF_API_BASE_URL);
  set('privacyPolicyUrl', overrides.LF_PRIVACY_POLICY_URL);
  set('supportUrl', overrides.LF_SUPPORT_URL);
  if (overrides.LF_APP_LINK_HOST) cfg.appLinks = { ...((cfg.appLinks as Config) ?? {}), host: overrides.LF_APP_LINK_HOST };
  if (overrides.LF_POSTHOG_KEY) cfg.analytics = { ...((cfg.analytics as Config) ?? {}), provider: 'posthog', posthogKey: overrides.LF_POSTHOG_KEY };
  if (overrides.LF_BUILD) cfg.build = Number(overrides.LF_BUILD);
  return cfg;
}

function serialize(cfg: Config): string {
  return JSON.stringify(cfg, null, 1) + '\n';
}

function fail(msg: string, errs: string[] = []): never {
  console.error(msg);
  for (const e of errs) console.error(`  - ${e}`);
  process.exit(1);
}

function main(argv: string[]) {
  const [cmd, a, b] = argv;
  switch (cmd) {
    case 'write': {
      if (!a) fail('usage: write <development|staging|production> [--out file]');
      const outIdx = argv.indexOf('--out');
      const out = outIdx > 0 ? resolve(argv[outIdx + 1]!) : resolve(root, 'apps/game/config/client.json');
      const cfg = build(a);
      const errs = validate(cfg);
      if (errs.length) fail(`client config for '${a}' is not releasable; nothing written:`, errs);
      writeFileSync(out, serialize(cfg));
      console.log(`Wrote ${out} (${a}, build ${String(cfg.build ?? 0)}, api ${String(cfg.apiBaseUrl)})`);
      return;
    }
    case 'check': {
      const errs = validate(readJson(resolve(a ?? 'apps/game/config/client.json')));
      if (errs.length) fail(`${a}: invalid`, errs);
      console.log(`${a}: valid`);
      return;
    }
    case 'inspect': {
      if (!a || !existsSync(a)) fail('usage: inspect <artifact.apk|aab> [expected.json]');
      const entry = a.endsWith('.aab') ? 'base/assets/config/client.json' : 'assets/config/client.json';
      let text: string;
      try {
        text = execFileSync('unzip', ['-p', a, entry], { encoding: 'utf8' });
      } catch {
        fail(`${a}: no ${entry} inside the artifact`);
      }
      const cfg = JSON.parse(text) as Config;
      const errs = validate(cfg);
      console.log(`${a}: packaged config environment=${String(cfg.environment)} build=${String(cfg.build ?? 0)} api=${String(cfg.apiBaseUrl)}`);
      if (errs.length) fail('packaged config is invalid:', errs);
      if (b && readFileSync(b, 'utf8') !== text) fail(`packaged config differs from ${b}`);
      if (b) console.log(`packaged config matches ${b}`);
      return;
    }
    case 'selftest': {
      const fx = readJson(resolve(root, 'apps/game/tests/fixtures/config-cases.json')) as { cases: { name: string; valid: boolean; config: Config }[] };
      let bad = 0;
      for (const c of fx.cases) {
        const errs = validate(c.config);
        if (errs.length === 0 !== c.valid) {
          bad++;
          console.error(`FAIL ${c.name}: expected ${c.valid ? 'valid' : 'invalid'}, got ${JSON.stringify(errs)}`);
        }
      }
      // The committed development config must be valid; the release templates must NOT be until filled in.
      if (validate(readJson(resolve(root, 'apps/game/config/client.json'))).length) {
        bad++;
        console.error('FAIL apps/game/config/client.json (development) is invalid');
      }
      for (const env of ['staging', 'production']) {
        if (validate(build(env, {})).length === 0) {
          bad++;
          console.error(`FAIL config/client/${env}.json validates without real values — it must contain placeholders only`);
        }
      }
      console.log(`client-config selftest: ${fx.cases.length + 3} checks, ${bad} failed`);
      process.exit(bad ? 1 : 0);
    }
    // falls through
    default:
      fail('usage: client-config.ts write|check|inspect|selftest');
  }
}

main(process.argv.slice(2));
