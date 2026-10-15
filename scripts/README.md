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
| `build-ios.sh` | `<env> [export\|simulator\|device\|archive] [--native] [--release]`: validated config, Godot iOS export to an Xcode project, export checks, then `xcodebuild` on macOS (exit 2 = BLOCKED without Xcode) |
| `ios/check-ios-export.py` | Xcode-project export validation without Xcode: packaged config (PCK), Info.plist, entitlements, pbxproj, opaque icon, native module |
| `ios/test-native-stub.sh` | Compiles the LoopFactoryIOS binding layer for the host (stub bridge) and tests it inside Godot 4.5.x |
| `check-platform-refs.py` | CI guard: shared GDScript may not reference platform-specific APIs outside `scripts/platform/` |
| `android/` | Fallback apksigner for environments without Google's Android SDK downloads |
| `loadtest/run.mjs` | autocannon load scenarios (results in `docs/load-testing.md`) |
