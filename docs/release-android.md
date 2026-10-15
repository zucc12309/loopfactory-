# Android release guide

The status of each artifact (as of 2026-10-15) is tracked in
[BETA_READINESS_IMPLEMENTATION.md](BETA_READINESS_IMPLEMENTATION.md#d-verification-evidence):
debug APK **built**; release AAB **not built**; nothing installed on a device; Play Console
acceptance **not tested**.

## Google Play requirements this build targets

Checked against developer.android.com on 2026-10-15. Re-check before every release.

* **Target API.** New apps and app updates must target **API 36** (from 2026-08-31; an
  extension to 2026-11-01 can be requested). The "Android AAB" preset sets `target_sdk=36`,
  `min_sdk=24`.
* **16 KB memory pages.** Apps targeting API 35+ must support them on 64-bit devices. Updates
  without it are blocked from 2027-02-01. `scripts/android/check-artifact.py` checks that every
  arm64/x86_64 `.so` has 2^14-aligned ELF LOAD segments. CI also runs
  `zipalign -c -P 16 -v 4` (build-tools 35+).
* **AAB.** New apps must be uploaded as Android App Bundles, which needs Godot's Gradle build.

## Engine: Godot 4.5.1 (not 4.3)

Measured on this project:

* Godot 4.3's Android templates ship 4 KB-aligned native libraries and target API 34. They
  can't meet the 16 KB rule.
* Godot 4.5.1's arm64 libraries are 16 KB-aligned.
* Every test suite and the E2E test pass on both versions, and the project still opens in 4.3.
* `build-android.sh` refuses to produce a release or AAB with Godot 4.3.

Migration notes (edge-to-edge on API 35+, orientation on large screens at API 36, `.uid` files)
are in the beta-readiness report.

## Toolchain

| Component | Version |
|---|---|
| Godot | **4.5.1-stable** + matching export templates |
| JDK | 17 |
| Android SDK | `platforms;android-36`, `build-tools;35.0.0`+, `platform-tools` |
| Gradle build template | Project → Install Android Build Template (Godot 4.5.1) → `apps/game/android/build` |
| Renderer | GL Compatibility |

**Editor Settings → Export → Android:** SDK path, Java SDK path and a debug keystore. The
headless equivalent is `~/.config/godot/editor_settings-4.5.tres`; see the CI `android` job.

## Build commands

```
scripts/build-android.sh debug                    # development config (loopback API), debug key
scripts/build-android.sh release staging|production   # sideloadable signed APK
scripts/build-android.sh aab staging|production       # Play upload (Gradle)
```

Each build:

1. Writes `apps/game/config/client.json` from `config/client/<env>.json` plus `LF_*` overrides,
   using `scripts/client-config.ts`. The build **fails before exporting** if the config has:
   * a loopback, private, `.example`/`.test` or placeholder host;
   * a non-HTTPS URL;
   * a missing privacy or support URL;
   * a missing `LF_BUILD`;
   * a test switch or a secret-looking field.
2. Sets `version/code` from `LF_BUILD` and, optionally, `version/name` from `LF_VERSION_NAME`.
3. Exports, then reads `assets/config/client.json` back **out of the artifact** and requires it
   to match the validated file byte for byte.
4. Runs `check-artifact.py`: ABIs, 16 KB alignment, and no test or editor files.
5. Prints the size and SHA-256.

The committed config and presets are restored afterwards.

To inspect any artifact by hand:
`npx tsx scripts/client-config.ts inspect <apk|aab> [expected.json]` and
`python3 scripts/android/check-artifact.py <apk|aab>`.

A debug APK talks to `http://127.0.0.1:8080`, which is the phone itself, so online features are
off on a device. For device testing against a real server, build `release staging` with an HTTPS
staging API.

## Versioning

* `version/name` follows the project version (`0.3.0`, betas `0.3.0-beta.N`).
* `version/code` must increase with every Play upload. Use the CI run number via `LF_BUILD`.

## Signing

* Generate the **upload key** once and store it in a password manager or CI secret store:
  `keytool -genkeypair -v -keystore upload.keystore -alias upload -keyalg RSA -keysize 4096 -validity 10000`
* Enrol in **Play App Signing**: Google holds the app signing key; you keep the upload key.
* Builds read it from the environment, never from files in Git:
  `GODOT_ANDROID_KEYSTORE_RELEASE_PATH`, `GODOT_ANDROID_KEYSTORE_RELEASE_USER`,
  `GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD`. (`*.keystore` and `*.jks` are git-ignored.)
* App Links need the SHA-256 of the **Play App Signing** certificate (Play Console → App
  integrity) in the API's `ANDROID_CERT_SHA256`. Add the upload key's fingerprint as well for
  internal builds.

## Upload, inspection and rollback

1. **Inspect** with `bundletool build-apks --bundle <aab> --output out.apks`, then
   `bundletool get-size total`. Also run `check-artifact.py <aab>`.
2. **Upload** to the **Internal testing** track first. Fill in the Data safety form to match
   [privacy-policy.md](privacy-policy.md): optional anonymous analytics, no advertising ID, no
   location.
3. **Roll out** to closed testing with a staged percentage.
4. **Roll back** by halting the rollout, or by promoting the previous release on that track. The
   API changes in this branch are additive (one nullable column), so old clients keep working.

## Test release checklist

- [ ] Installs and launches on a low-end (2–3 GB RAM, Android 8–10) and a recent device.
- [ ] Cold start to home < 2 s; no frame drops while rotating/running on the low-end device.
- [ ] Airplane mode: campaign, endless, offline daily practice all playable; progress persists.
- [ ] Kill the app mid-level and mid-run → resumes on the editable board with moves intact.
- [ ] Back button: closes overlays, then navigates back, then exits from Home.
- [ ] Reconnect: queued completions sync; daily submission appears on the leaderboard.
- [ ] Vibration, sound and music toggles work independently; reduced motion removes transitions,
      pre-tilt, confetti and the long celebration; larger shape symbols visible.
- [ ] Game feel on device: tap response feels immediate, rotation snap (140 ms) is neither sluggish
      nor jittery, haptic strength is subtle, music sits under the effects (−17 dB).
- [ ] Frame time while running the 6×7 boards (levels 33–36) on the low-end device; record it in
      docs/performance.md.
- [ ] Incoming call / home button mid-run: `app_background` then `app_resume`; board resumes editable.
- [ ] Friend challenge: create on device A, enter the code on device B (fresh install, no sign-up).
- [ ] Share: Copy text works; native share sheet only in a build with the share plugin.
- [ ] Notch / gesture-bar devices: nothing clipped (safe-area margins).
- [ ] Delete account works online; offline it explains that the server copy needs a connection.
- [ ] Data safety form in Play Console matches docs/privacy-policy.md.
- [ ] Pre-launch report (Play Console) has no crashes.
