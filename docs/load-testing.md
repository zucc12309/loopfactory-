# Load testing — measured results

Harness: `scripts/loadtest/run.mjs` (autocannon). Run date: 2026-10-15. Raw JSON:
`docs/load-test-results/`.

## Environment (important for interpreting the numbers)

* **One 4-vCPU / 15 GB VM ran everything at once:** the API, PostgreSQL 16 and the load
  generator (autocannon with up to 1,000 sockets). The generator alone consumes a large share of
  CPU at 1,000 connections, so these are conservative, environment-bound numbers — not a
  production capacity guarantee.
* API: production bundle (`NODE_ENV=production`), rate limiting disabled (otherwise a single source
  IP is throttled by design), `LOG_LEVEL=warn`, Prisma pool 10 per process.
* 300 guest accounts created up front; each scenario ran 20 s.

## Scenarios

* `daily_read_spike` — `GET /api/v1/challenges/daily` (everyone opening today's puzzle).
* `authenticated_mix` — round-robin of `GET /player/me`, `POST /progress/sync` (one settings op
  with a fresh opId) and `GET /challenges/daily/leaderboard`, with rotating bearer tokens.
* `daily_submit_spike` — `POST /challenges/daily/submit` with a valid replay and unique
  submission ids (full server-side re-simulation, leaderboard + weekly + achievement updates in a
  transaction).

## Results: baseline (single process) → after optimisation (2 workers)

Optimisations between runs: listen backlog 4096 (the default 511 caused connection resets at 1,000
sockets), in-process cache of the immutable daily challenge, `WEB_CONCURRENCY=2` cluster mode.

| Scenario | Conns | Req/s | Latency p50 / p99 (ms) | Error rate | API CPU avg | API RSS max (MB) | DB conns max |
|---|---|---|---|---|---|---|---|
| daily_read_spike | 100 | 1680 → **4462** | 56 / 146 → **19 / 102** | 0% → **0%** | 186.9% → 197.7% | 209.5 → 453.6 | 21 → 12 |
| authenticated_mix | 100 | 530 → **548** | 152 / 409 → **151 / 431** | 0% → **0%** | 233.7% → 259.5% | 226.9 → 478.6 | 21 → 21 |
| daily_submit_spike | 100 | 240 → **306** | 408 / 590 → **319 / 614** | 0% → **0%** | 218.3% → 246.7% | 225.5 → 483.2 | 21 → 21 |
| daily_read_spike | 1000 | 1598 → **5175** | 211 / 439 → **130 / 288** | 3.499% → **0.222%** | 190.9% → 208.4% | 232.6 → 501.1 | 21 → 21 |
| authenticated_mix | 1000 | 384 → **464** | 1758 / 12782 → **1987 / 4341** | 0% → **0%** | 228.2% → 259.5% | 405.2 → 703.3 | 21 → 21 |
| daily_submit_spike | 1000 | 179 → **236** | 4401 / 17348 → **3621 / 6640** | 0% → **0%** | 224.1% → 241.6% | 405.8 → 708 | 21 → 21 |

CPU is the sum over API processes (100 % = one core). DB connections include the sampler's own
connection; they stay bounded by `workers × DB_POOL_SIZE`.

## Findings

1. **No failed requests at 100 concurrent connections** in any scenario (0 errors, 0 non-2xx).
2. **1,000 concurrent connections:** the read spike is served at ~5,200 req/s with p99 288 ms and
   0.22 % socket errors (timeouts at the generator; was 3.5 % before the backlog fix). The write
   paths stay correct (0 errors) but queue: p50 ≈ 2 s for the authenticated mix and ≈ 3.6 s for
   submissions — the box is CPU-saturated.
3. The bottleneck is CPU in the API (JSON, Prisma query engine, validation) — the database pool
   never exceeded its limit and Postgres was not the limiting factor. Memory stayed < 0.75 GB for
   two workers.
4. Translating to players: a playing user issues roughly one request every 30–60 s (sync after a
   level, occasional leaderboard), so ~500 req/s of authenticated traffic corresponds to the order
   of 15,000–30,000 concurrently active players **on this single shared VM**.

## Recommendations for launch-day spikes

* Serve `GET /challenges/daily` and `GET /levels*` through a CDN (responses already carry
  `Cache-Control`), which removes the largest spike entirely from the API.
* Run ≥ 2 instances × `WEB_CONCURRENCY` = vCPUs; size Postgres connections accordingly
  (PgBouncer beyond ~100) and move rate limiting to a shared store.
* Re-run this harness against a staging deployment with the load generator on a separate machine
  before launch: `node scripts/loadtest/run.mjs https://staging.example <pid-or-0> 60`
  (CPU sampling via `/proc` only works when the generator runs on the API host).
