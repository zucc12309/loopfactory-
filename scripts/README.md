# Scripts

| Script | Purpose |
|---|---|
| `build-levels.ts` (`npm run levels:build`, `levels:check`) | Solve/verify the curated campaign and write level + achievement data for API and game |
| `levels/curated-source.ts` | **Edit this** to add or change campaign levels |
| `build-parity-fixtures.ts` (`npm run fixtures:build`, `fixtures:check`) | TS → GDScript parity fixtures |
| `test-game.sh` | Godot headless tests; fails on any GDScript error |
| `e2e.sh` | Starts the API on a scratch port and runs the real client against it |
| `build-android.sh` | `debug` / `release <env>` / `aab <env>` with a validated, re-inspected client config (Godot 4.5.1 for release) |
| `client-config.ts` | Write/check/inspect the client config per environment; `selftest` runs the shared rules (`npm run config:check`) |
| `android/check-artifact.py` | APK/AAB inspection without the SDK: ABIs, 16 KB ELF alignment, packaged config, no test files |
| `android/` | Fallback apksigner for environments without Google's Android SDK downloads |
| `loadtest/run.mjs` | autocannon load scenarios (results in `docs/load-testing.md`) |
