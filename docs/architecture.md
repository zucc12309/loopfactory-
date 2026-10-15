# Architecture

```
loop-factory/
├─ apps/game/                Godot 4.3 client (GDScript, GL Compatibility renderer, portrait)
│  ├─ scripts/engine/        GDScript port of the rules engine (parity-tested against TS)
│  ├─ scripts/core/          autoloads: Game (state+autosave), Net (API+sync), Sfx, Analytics
│  ├─ scripts/ui/            design system, board renderer, screens
│  ├─ data/                  curated levels + achievements (generated from packages/*)
│  ├─ tests/                 headless unit tests (parity, rules, save/resume, compile-all)
│  └─ tests_e2e/             client ↔ API end-to-end test
├─ services/api/             Node 22 + TypeScript + Express REST API
├─ packages/engine/          canonical rules engine: simulation, solver, generator, replay verify
├─ packages/contracts/       Zod request/response schemas (validation + OpenAPI source)
├─ database/                 Prisma schema + versioned SQL migrations (PostgreSQL 16)
├─ infrastructure/docker/    API container
├─ scripts/                  level build, parity fixtures, test runners, load test
└─ docs/                     this documentation
```

## Key decisions

**One rules engine, two runtimes, proven identical.** The device must play offline (simulation,
solver for hints, generator for endless/practice) and the server must verify competitive replays.
The TypeScript engine is canonical; the GDScript port is mechanically mirrored and checked against
fixtures generated from TS (`npm run fixtures:build`, `apps/game/tests/test_parity.gd`). All
randomness is an integer xorshift32 stream so generation is bit-identical across platforms.

**Scores are derived from replays, never from client counters.** Daily submissions, campaign and
endless completions carry the move list; the server re-applies moves, re-simulates and counts
rotations itself. Elapsed time is not used for ranking because it cannot be verified.

**Offline-first.** Local state is the source of truth for play; the server is synchronised through
an idempotent operation queue with per-domain merge rules (`docs/sync.md`).

**No Redis (yet).** Nothing currently needs it: rate limiting is per instance in memory, daily
generation is lazy + race-safe through a unique constraint, and maintenance runs as a daily cron.
When scaling past one API instance, add a shared rate-limit store (Redis) — see `deployment.md`.

**Route registry.** Each endpoint is declared once (`services/api/src/routes/index.ts`) with its
Zod schemas; the same declaration validates requests, types the handler and produces the OpenAPI
3.1 document (`docs/api/openapi.json`, served at `/openapi.json`). Specific paths such as
`/levels/packs` are registered before `/levels/:id`, and a test asserts they are not shadowed.

**Godot client structure.** UI is built in code from a small design system (`LFStyle` tokens,
`LFIcons` vector icons, `LFBoardView` custom drawing) — no image assets except the app icon and
the OFL Nunito font; sound effects are synthesised at startup. The GL Compatibility renderer and
`low_processor_mode` keep battery use low on mid-range Android phones: the board only redraws while
something animates.

## Data flow

```
tap ──> LFGameState.rotate ──> autosave (atomic) ──> board animates
Run ──> LFSimulation.simulate (deterministic frames) ──> LFBoardView interpolates
win ──> complete_active ──> progress/achievements ──> sync queue ──> Net.sync ──> API
API ──> verifyReplay (engine) ──> Postgres (transaction) ──> leaderboards ──> snapshot ──> merge
```

## Backend modules

| Module | Responsibility |
|---|---|
| `services/tokens.ts` | HS256 access JWT (15 min), opaque 256-bit refresh tokens (hash stored), rotation with reuse detection (family revocation) |
| `services/identity.ts` | Google / Apple ID-token verification via JWKS; dev provider for tests |
| `services/progress.ts` | idempotent sync, replay verification, merge snapshot |
| `services/daily.ts` | HMAC-seeded daily generation, submission window, verification |
| `services/leaderboards.ts` | daily / ISO-weekly / global boards (lower score wins, earliest tie) |
| `services/achievements.ts` | stats + idempotent achievement grants |
| `services/privacy.ts` | data export, erasure (cascading delete, salted-hash audit record) |
| `services/purchases.ts` | store verification abstraction (Play / App Store pending credentials) |
| `services/monitoring.ts` | error-reporter adapter (Sentry when configured) |
