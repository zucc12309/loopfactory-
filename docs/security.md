# Security review

Status at the time of writing: **no known unresolved critical issues.** Items below are either
implemented (✔) or explicitly tracked as pending (◻).

## Authentication & sessions
* ✔ Guest accounts are created by the server; the client never chooses its player id.
* ✔ Access tokens: HS256 JWT, 15 min, issuer/audience checked, algorithm pinned.
* ✔ Refresh tokens: 256-bit random, stored as SHA-256 hashes, single use. Reuse of a rotated
  token revokes the entire token family (stolen-token detection); concurrent rotation is guarded by
  a conditional update (tested). Logout revokes the family. Tokens expire after 90 days.
* ✔ Account linking verifies Google/Apple ID tokens against provider JWKS with audience pinning.
  The dev provider is refused at startup in production.
* ✔ Production startup fails if secrets contain placeholder values or dev providers are enabled.
* ◻ Device attestation (Play Integrity / App Attest) for guest creation — recommended before
  significant marketing spend to raise the cost of leaderboard sock-puppets.

## Input handling
* ✔ Every body/query validated with Zod (strict objects reject unknown fields); 256 KB body limit;
  replays capped at 500 moves; sync batches at 100 ops.
* ✔ All SQL goes through Prisma parameterisation or tagged-template `$queryRaw` (no string SQL
  with user input). The single `$executeRawUnsafe` is in test helpers only.
* ✔ Display names: length/charset validation + blocklist; rendered as plain text by the client.
* ✔ Untrusted boards (saves, network) are validated (`validateBoard` / `LFTiles.validate_board`).

## Competitive integrity
* ✔ Scores come from server re-simulation of replays; unverified completions never rank.
* ✔ Daily seeds are HMAC(secret, date): future puzzles cannot be precomputed; the published daily
  omits its solution; future dates return 404.
* ✔ Submission idempotency (player, submissionId) and rate limits (20/min/player).
* ◻ A determined player can still use an external solver; rankings are by rotations, and par is
  the proven optimum, so the leaderboard top will saturate at par. Ties break by server time.

## Transport, headers, logging
* ✔ HTTPS terminated by the platform (Render); HSTS via Helmet; `x-powered-by` disabled; CORS
  closed by default.
* ✔ Structured logs with redaction of authorization headers and token fields; request ids.
* ✔ Errors return a uniform envelope without stack traces.

## Rate limiting
* ✔ Global 600/min/IP; guest creation 30/h/IP; auth 30/min; sync 60/min/player; submissions
  20/min/player; privacy 10/h/player. ◻ In-memory per instance — use a shared store when scaling out.

## Data protection & privacy
* ✔ Data minimisation: no email required, no device identifiers, analytics id is random and
  consent-gated. Optional provider email is stored only for account recovery support and never
  returned by public endpoints.
* ✔ Export (`GET /privacy/export`) and erasure (`POST /privacy/delete-request`, `DELETE /player/me`)
  with cascading deletes; an audit row keeps only a salted hash.
* ✔ Retention job (`maintenance.ts`): refresh tokens, sync ops (90 d), invalid submissions (30 d).
* ✔ Local export never includes tokens.

## Database least privilege
Run migrations with an owner role and the API with a restricted role:
```sql
CREATE ROLE loopfactory_app LOGIN PASSWORD '…';
GRANT CONNECT ON DATABASE loopfactory TO loopfactory_app;
GRANT USAGE ON SCHEMA public TO loopfactory_app;
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO loopfactory_app;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO loopfactory_app;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO loopfactory_app;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT USAGE, SELECT ON SEQUENCES TO loopfactory_app;
```

## Supply chain
* ✔ `npm audit --omit=dev` clean (a vulnerable transitive `deepmerge-ts` in the Prisma CLI is
  overridden to the patched 8.x). CI runs audit + gitleaks on every PR.
* ✔ Lockfile committed; container runs as the unprivileged `node` user.

## Client
* ✔ No secrets in the client: `config/client.json` contains only the public API URL and optional
  public analytics key. Release signing keys are never committed (`.gitignore`).
* ✔ Save files carry an integrity checksum (detects corruption, not tampering — local
  progress is the player's own; anything competitive is verified server-side).
