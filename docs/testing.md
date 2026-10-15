# Testing

| Suite | Command | What it covers | Result (2026-10-15) |
|---|---|---|---|
| Engine unit tests | `npm test -w @loopfactory/engine` | masks/rotation, movement, corners, multi-package spawning, merge priority, head-on deadlock, loop detection, wrong dock, off-board, crossings, determinism, illegal moves, tick bound; solver vs **brute force** minimum, unsolvable/budget reporting, hints converge; generator validity for every tier, determinism, replay verification | 35/35 pass |
| Game tests (Godot, headless) | `./scripts/test-game.sh` | **TS↔GDScript parity** (RNG, 170 simulations incl. full frame streams, 34 solver runs incl. node counts, hints, 15 generated levels); rotate/undo/reset; locked tiles; completion only when really solved; monotonic best; resume after restart; tampered save rejected; corrupted/truncated/interrupted save recovery; sync-queue coalescing/backoff; merge rules; unlocking; endless determinism; offline-daily labelling; daily replay queueing; every script compiles | 26 tests / 1,794 assertions pass |
| API integration | `npm test -w @loopfactory/api` (needs Postgres) | guest auth, refresh rotation + reuse detection, concurrent rotation, logout, link/switch (reinstall restore), provider gating, rate limiting, name moderation; sync apply/duplicate/concurrent duplicates, forged replays, unverified clamping + upgrade, out-of-order offline completions, settings & active-puzzle LWW (multi-device), endless verification, validation, history, isolation; levels pagination and route shadowing; daily reproducibility, hidden solution, future-date 404, submission verification, ranking & ties, duplicate submissions, closed window, weekly board, achievements; global leaderboard verified-only; config ETag; OpenAPI coverage of all required endpoints; error envelope; privacy export/erasure; purchases | 35/35 pass |
| End-to-end | `./scripts/e2e.sh` | real Godot client autoloads + real API: offline play queues ops → reconnect → guest auth → sync drains queue → daily downloaded without solution → solved with on-device solver → replay submitted → appears on leaderboard with verified rotations → snapshot restores progress | 16/16 checks pass |
| Content checks | `npm run levels:check`, `npm run fixtures:check`, `npm run openapi -w @loopfactory/api -- --check` | generated files are up to date | pass |
| Static | `npm run typecheck`, `npm run lint`, `npm audit --omit=dev` | | pass, 0 vulnerabilities |
| Migrations | CI: `prisma migrate deploy` on empty DB + `migrate diff --exit-code` | schema/migration drift | pass locally |
| Visual QA tour | `godot --path apps/game -- --tour=/abs/dir` | drives every screen and a full solve/fail through UI code, saves screenshots | run on desktop build and on the **exported APK contents** with no script errors |
| Load | `node scripts/loadtest/run.mjs` | see `docs/load-testing.md` | measured |
| Container | Docker build + run | migrate → seed → serve as non-root; healthcheck healthy; prod refuses placeholder secrets | pass (sandbox used a registry mirror + full Debian base, see deployment.md) |

## Not covered by automated tests
* On-device behaviour (touch latency, haptics, audio output, Android lifecycle events) — needs a
  physical device; see the checklist in `docs/release-android.md`.
* Google/Apple ID-token verification against real providers (requires client IDs).
* Store purchase verification (requires store credentials).
