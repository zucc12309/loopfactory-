# Backend deployment & operations

> Nothing in this repository deploys automatically or creates cloud resources. Applying
> `render.yaml` creates billable services — review plans and regions first.

## Environments

| | Development | Production |
|---|---|---|
| Start | `docker compose up --build` or `npm run dev -w @loopfactory/api` | Render (Docker) |
| Database | local Postgres 16 | Render managed Postgres 16 (Singapore) |
| Dev auth / purchases | enabled | **refused at startup** |
| Secrets | `.env` (from `.env.example`) | Render env vars (`generateValue` / dashboard) |

## Environment variables

| Variable | Required | Notes |
|---|---|---|
| `DATABASE_URL` | yes | Postgres connection string (use the restricted app role, see security.md) |
| `JWT_SECRET` | yes | ≥ 32 random chars; rotating it signs everyone out (refresh still works) |
| `DAILY_SEED_SECRET` | yes | ≥ 16 chars. **Never change after launch**: it defines every daily puzzle |
| `PRIVACY_HASH_SALT` | yes | ≥ 16 chars, salts erasure audit hashes |
| `PORT` | no | default 8080 |
| `WEB_CONCURRENCY` | no | worker processes (≈ vCPUs). Default 1 |
| `DB_POOL_SIZE` | no | Prisma pool **per worker** (default 10). Keep workers × pool < DB max connections |
| `TRUST_PROXY` | no | proxy hops (Render: 1) for correct client IPs in rate limiting |
| `GOOGLE_CLIENT_IDS` | for Google linking | comma-separated OAuth client IDs |
| `APPLE_BUNDLE_IDS` | for Apple linking | comma-separated bundle IDs |
| `SENTRY_DSN` | optional | also `npm i @sentry/node` in services/api |
| `CORS_ORIGINS` | optional | only for browser clients; mobile needs none |
| `LOG_LEVEL` | optional | `info` default |
| `ENABLE_DEV_AUTH`, `ENABLE_DEV_PURCHASES` | dev only | must be `false` in production |
| `RATE_LIMIT_DISABLED` | test only | |

## First deployment on Render

1. Push the repository to GitHub; in Render choose **New → Blueprint** and select `render.yaml`.
2. Review the plans (`starter` web, `basic-256mb` Postgres) and region, then apply.
3. Set `GOOGLE_CLIENT_IDS` / `APPLE_BUNDLE_IDS` / `SENTRY_DSN` when available.
4. Each deploy runs `preDeployCommand`: `prisma migrate deploy` + idempotent seed (levels,
   achievements, initial remote config). A failing migration aborts the deploy; the old version
   keeps serving.
5. Health check path `/ready` (checks the database); `/health` is liveness only.
6. Put the HTTPS URL into `apps/game/config/client.json` (`apiBaseUrl`) for release builds.

Railway works the same way: Docker service from `infrastructure/docker/api.Dockerfile`, a
Postgres plugin, the same variables, and the migrate+seed command as a release command.

## Migrations

* Author: edit `database/schema.prisma`, run `npm run db:migrate:dev -w @loopfactory/api -- --name <change>`;
  commit the generated SQL in `database/migrations/`.
* CI applies all migrations to an empty database and fails if schema and migrations drift.
* Production: `prisma migrate deploy` only (never `migrate dev`/`db push`).
* Prefer expand → migrate → contract for breaking changes (add column, deploy code that writes
  both, backfill, then remove the old column in a later release) so rollbacks stay possible.

## Rollback

* **Code:** Render → service → Deploys → *Rollback* to the previous image (instant). Because
  migrations are additive (expand/contract), the previous image remains compatible.
* **Bad migration:** write a new forward migration that reverts it; do not edit applied migrations.
* **Data:** restore from backup (below) into a new database, then repoint `DATABASE_URL`.

## Backups & recovery

* Render Postgres paid plans include daily backups with point-in-time recovery (check the plan's
  retention). Additionally schedule a weekly logical dump to object storage:
  `pg_dump --format=custom --no-owner "$DATABASE_URL" > loopfactory-$(date +%F).dump`
* Restore drill (do it before launch and quarterly):
  `createdb lf_restore && pg_restore --no-owner -d lf_restore loopfactory-YYYY-MM-DD.dump`,
  run the API against it, hit `/ready` and a few read endpoints.
* RPO target 24 h (dumps) / minutes (PITR); RTO target 1 h.

## Scheduled jobs

`loopfactory-maintenance` (cron, 00:15 UTC): retention cleanup (`maintenance.ts`) and
pre-generation of the next 3 dailies (`pregenerate-daily.ts`). Daily generation is also lazy and
race-safe, so a missed cron run never blocks players.

## Monitoring

* Logs: structured JSON (pino) to stdout with request ids — Render log streams can forward to
  Better Stack / Datadog / Grafana Loki.
* Errors: Sentry adapter (`SENTRY_DSN`, optional `@sentry/node`).
* Alerts to configure: `/ready` failing, 5xx rate > 1 %, p95 latency > 500 ms, DB connections
  > 80 % of max, disk > 80 %.
* Product metrics: see `docs/analytics.md`.

## Scaling notes (from the load test in docs/load-testing.md)

* One Node process saturates on CPU (JSON + Prisma) before the database does. Scale with
  `WEB_CONCURRENCY` and/or more instances; each instance multiplies DB connections
  (`instances × workers × DB_POOL_SIZE`). Add PgBouncer before exceeding ~100 connections.
* With more than one instance, move rate limiting to a shared store (`rate-limit-redis`) —
  this is the first point where adding Redis is justified.
* The daily puzzle is cached per process and served with `Cache-Control: max-age=600`; put a CDN
  in front of `GET /api/v1/challenges/daily` and `GET /api/v1/levels*` for launch-day spikes.
