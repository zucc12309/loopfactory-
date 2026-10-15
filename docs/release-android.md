# Android release guide

## What has been verified in this repository's build environment

* `scripts/build-android.sh debug` → `apps/game/build/loopfactory-debug.apk` (≈48 MB, arm64-v8a +
  armeabi-v7a), signed with v1+v2+v3 schemes, zipalign verified.
* `scripts/build-android.sh release` with a throwaway upload key → `loopfactory-release.apk`
  (≈46 MB), signature and alignment verified.
* The exported project (exactly what the APK contains) was run on desktop Godot through the full
  UI tour without script errors; tests are excluded and level/config JSON is included.
* **Not verified:** installation and play on a physical device or emulator (no Android device or
  emulator was available). Do this first — see the release checklist below.

The sandbox could not download Google's Android SDK (`dl.google.com` is blocked there), so it used
`scripts/android/setup-sandbox-signer.sh`: a small `apksigner`-compatible CLI on top of Google's
`apksig` library plus an `adb` stub. **On a normal machine install the real SDK instead.**

## Toolchain

| Component | Version |
|---|---|
| Godot | 4.3-stable + matching export templates |
| JDK | 17 (21 also works for non-Gradle export) |
| Android SDK | platform-tools, build-tools 34.x (apksigner), platforms;android-34 |
| Renderer | GL Compatibility (broadest support on mid-range devices) |

Editor Settings → Export → Android: SDK path, Java SDK path, debug keystore (Godot can create
one). Headless equivalent: `~/.config/godot/editor_settings-4.3.tres` (see the CI `android` job).

## Versioning

* `version/name` (e.g. `0.1.0`) mirrors `application/config/version` in `project.godot`.
* `version/code` must increase for every Play upload. Use `MAJOR*10000 + MINOR*100 + PATCH`
  (0.1.0 → 100) or the CI run number.

## Signing

* Generate the **upload key** once and store it in a password manager / CI secret store:
  `keytool -genkeypair -v -keystore upload.keystore -alias upload -keyalg RSA -keysize 4096 -validity 10000`
* Enrol in **Play App Signing** (Google holds the app signing key; you keep the upload key).
* Provide to builds via environment, never files in git:
  `GODOT_ANDROID_KEYSTORE_RELEASE_PATH`, `GODOT_ANDROID_KEYSTORE_RELEASE_USER`,
  `GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD`. (`*.keystore`/`*.jks` are git-ignored.)

## Play Store package format (AAB)

Google Play requires an Android App Bundle for new apps. Godot produces AABs only with the
**Gradle build**: Project → Install Android Build Template, then set
`gradle_build/use_gradle_build=true`, `gradle_build/export_format=1` (AAB) and
`gradle_build/target_sdk=35` (Play's target-API requirement for new apps/updates in 2025–26 —
check the current requirement), `min_sdk=24`. Gradle needs network access to Google's Maven, so
build AABs on a developer machine or in CI (the `android` CI job is the starting point).

## Before production

1. Set `apps/game/config/client.json` → `apiBaseUrl` to the HTTPS production API,
   `environment: production`, analytics provider/key if used (public key only).
2. Bump `version/code` and `version/name`.
3. `scripts/build-android.sh release` (or the Gradle AAB export).
4. Upload to an **internal testing** track first.

## Test release checklist

- [ ] Installs and launches on a low-end (2–3 GB RAM, Android 8–10) and a recent device.
- [ ] Cold start to home < 2 s; no frame drops while rotating/running on the low-end device.
- [ ] Airplane mode: campaign, endless, offline daily practice all playable; progress persists.
- [ ] Kill the app mid-level and mid-run → resumes on the editable board with moves intact.
- [ ] Back button: closes overlays, then navigates back, then exits from Home.
- [ ] Reconnect: queued completions sync; daily submission appears on the leaderboard.
- [ ] Vibration and sound toggles work; reduced motion removes transitions; colour symbols visible.
- [ ] Notch / gesture-bar devices: nothing clipped (safe-area margins).
- [ ] Delete account works online; offline it explains that the server copy needs a connection.
- [ ] Data safety form in Play Console matches docs/privacy-policy.md.
- [ ] Pre-launch report (Play Console) has no crashes.
