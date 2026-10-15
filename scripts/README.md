# Scripts

| Script | Purpose |
|---|---|
| `build-levels.ts` (`npm run levels:build`, `levels:check`) | Solve/verify the curated campaign and write level + achievement data for API and game |
| `levels/curated-source.ts` | **Edit this** to add or change campaign levels |
| `build-parity-fixtures.ts` (`npm run fixtures:build`, `fixtures:check`) | TS → GDScript parity fixtures |
| `test-game.sh` | Godot headless tests; fails on any GDScript error |
| `e2e.sh` | Starts the API on a scratch port and runs the real client against it |
| `build-android.sh` | Export debug/release APKs |
| `android/` | Fallback apksigner for environments without Google's Android SDK downloads |
| `loadtest/run.mjs` | autocannon load scenarios (results in `docs/load-testing.md`) |
