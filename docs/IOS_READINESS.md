# iOS readiness

**Branch:** `claude/ios-readiness` (from `claude/android-beta-readiness` @ `6ac1166`) ·
**Date:** 2026-10-15 · **Engine target:** Godot 4.5.1 (same as Android)

**Verdict: iOS SOURCE READY.** The game, the shared platform layer, the iOS export configuration,
the build pipeline, the native module source and the server side of Universal Links are in place.
The Xcode project **exports and validates on Linux** with the real Godot 4.5.1 iOS template.
Nothing has been **compiled with the iOS SDK, run in a simulator, or installed on an iPhone**,
because no macOS/Xcode machine was available. That is the only reason this is not "iOS BUILD
READY". The next step is one command on a Mac ([IOS_BUILD_RUNBOOK.md](IOS_BUILD_RUNBOOK.md)).

Related: [IOS_BUILD_RUNBOOK.md](IOS_BUILD_RUNBOOK.md) (exact Mac/iPhone steps) ·
[IOS_DEVICE_TEST_MATRIX.md](IOS_DEVICE_TEST_MATRIX.md) (what to test, with evidence levels).

---

## 1. Initial audit (state at `6ac1166`, before any change)

The existing iOS preset was **not** evidence of compatibility. Exporting it with Godot 4.5.1 failed
immediately ("App Store Team ID not specified"), and with a team set it showed further problems.

| Area | Found | Risk |
|---|---|---|
| iOS export preset | Written for Godot 4.3: iOS 14, `.ipa` export path, no team, several 4.3 option names that 4.5 ignores (`capabilities/push_notifications`), 12 per-size icons all pointing at the 1024 px PNG | Export refused; options silently ignored |
| App icon | `icon-1024.png` is RGBA with transparent corners. Godot 4.5.1 warns "must be opaque" | App Store rejects icons with alpha |
| Purpose strings | Camera/mic/photo-library keys present but **empty**; no `NSPhotoLibraryAddUsageDescription` | Choosing "Save Image" in a share sheet **crashes** an app without that key; empty strings get flagged at upload |
| Shared code → Android-only | `share.gd` looked up the `LoopFactoryShare` singleton directly; links were read once at the splash only (Android intent); settings called `OS.shell_open`; haptics called `Input.vibrate_handheld` | No iOS path for sharing or links; warm links (app already running) never routed on either platform |
| Platform branching in gameplay | None. No `OS.get_name()` comparisons; the puzzle engine, solver, saves and UI are platform-neutral | — |
| File access / saves | `user://` with atomic temp + rename and `.bak` recovery; works on iOS (app container `Documents`, which iCloud device backup includes) | Refresh token stored in plaintext in the save |
| HTTP | `HTTPRequest`, HTTPS in release configs (enforced by `client-config.ts`) | ATS blocks plain-HTTP dev servers on a device |
| Audio | No iOS session setting (engine default) | Behaviour with the silent switch and other apps' music undefined |
| Display | Safe area from `DisplayServer.get_display_safe_area()` used by every screen; portrait; `canvas_items` + `expand` | Never tested against iPhone insets |
| Lifecycle | Saves on `PAUSED`/`FOCUS_OUT`/close | No memory-warning handling (iOS may kill a backgrounded app) |
| Renderer | GL Compatibility → OpenGL ES 3.0 on iOS | Works but Apple-deprecated; fine for this 2D game (see §10) |
| Native needs | Share sheet, Universal Links; optionally Keychain and the Reduce Motion preference | Need native code (Godot has no built-in share or link API on iOS) |
| Tooling here | Godot 4.3 and 4.5.1 (Linux), Godot 4.5.1 iOS template (extracted from the official `.tpz`), godot-cpp `godot-4.5-stable`, clang, SCons. **No macOS, Xcode, iOS SDK or simulator.** CocoaPods: not needed (no pods) | Compile and run steps blocked |
| Baseline tests | engine 46, API 70, Godot 59 tests / 7,771 assertions, auth 32, analytics 74, UI 301, crew 201, beta 173, E2E 28, config 26: all pass | — |

## 2. Architecture

```
 screens / game logic (shared, platform-neutral)
        │  LFShare (codes, links)      Game (saves)       main.gd (link routing)
        ▼
 LFPlatform  scripts/platform/platform_services.gd   ← the ONLY door to platform features
        │  share_text · share_image · share_file · open_external_url · consume_launch_uri
        │  supports_native_sharing/deep_links/haptics/secure_storage · vibrate
        │  secure_get/set/delete · system_reduce_motion · prune_share_files
        ├── LFIOSAdapter      ── "LoopFactoryIOS" GDExtension   (ios/loopfactory-native)
        ├── LFAndroidAdapter  ── "LoopFactoryShare" Godot plugin (android/share-plugin, unchanged)
        └── LFPlatformAdapter ── safe fallback: desktop, editor, any build without a native module
```

* Selection happens once, lazily: iOS singleton (if its API version matches), else the Android
  singleton, else the fallback. Native modules are **optional**: a build without them plays fully
  and offers copy-text and manual code entry.
* Results are honest. `chooser_opened`, `unavailable`, `failed` and `invalid_file` are the only
  share outcomes. iOS can additionally report that the sheet closed (`completed`, `cancelled` or
  `failed`), tracked as `share_sheet_closed`. "completed" means the chosen activity said it
  finished, **not** that anyone received anything.
* `scripts/check-platform-refs.py` (CI) fails if shared GDScript uses native singletons, Java/JS
  bridges, platform-name feature checks, branches on `OS.get_name()`, or calls
  `Input.vibrate_handheld` / `OS.shell_open` outside `scripts/platform/`. Current tree: 42 shared
  scripts, 0 references.

## 3. Compatibility matrix (after this work)

Evidence: **Auto** = automated test (desktop Godot / simulated iOS geometry and events / host
build of the native binding layer) · **Export** = verified in the real Godot 4.5.1 iOS export ·
**—** = not verified. Nothing here is verified on a Simulator or an iPhone.

| Area | Status | Evidence | Remaining |
|---|---|---|---|
| Puzzle engine, 36 levels, hints, undo/reset, daily, Crew, cosmetics | Shared code, identical on both platforms | Auto (parity fixtures, unit, UI, crew, E2E) | On-device play-through |
| Xcode project export | Works on Linux with the official template | Export: 26 checks (dev), 27 (staging) | — |
| Compile with the iOS SDK | Not done | — | **BLOCKED: needs macOS + Xcode** |
| Bundle id, version, build number, team, provisioning | From the environment (`LF_IOS_*`, `LF_BUILD`); nothing personal committed | Export | — |
| Portrait, iPhone-only, iOS 15.0+, arm64 | Configured | Export (Info.plist, pbxproj) | — |
| App icon / launch screen | Opaque 1024 px icon (Xcode single-size); storyboard with brand colour | Export | Visual check on device |
| Purpose strings / permissions | Add-to-Photos (Save Image) explained; camera/mic/photo-read state "not used"; **no** tracking, push, location or ATT | Export | — |
| ATS / networking | HTTPS only in staging/production; `NSAllowsLocalNetworking` + Local Network text only in development | Export (both directions checked) | Device network test |
| Safe areas (notch, Dynamic Island, home indicator) | Every screen already used the safe area; now tested | Auto: 4 iPhone geometries × 8 screens, mutation-checked | Real devices |
| Touch: tap, long-press reverse, drag/scroll | Same input code as Android | Auto (desktop pointer events) | Device feel |
| Keyboard (code / name fields) | Fields near the top; Godot shows the iOS keyboard | — | Device |
| Reduced motion | In-game setting; on iOS seeded once from the system Reduce Motion | Auto (fake native value) | Device |
| Background / resume / termination | Save on pause; save + diagnostic on memory warning; links polled on resume | Auto | Device |
| Audio: silent switch, other apps' music | Ambient session, mix with others (project settings) | — | Device (D4–D6) |
| Audio interruptions | Handled by Godot's iOS app delegate | — | Device |
| Saves (`user://`, atomic) | Unchanged, platform-neutral | Auto (corruption, recovery) | Device restart |
| Refresh token storage | Keychain on iOS with the native module; file elsewhere (unchanged) | Auto + host native binary | Device Keychain |
| Offline play / sync / reconnect | Unchanged | Auto (E2E) | Device |
| Native share sheet | Implemented (UIActivityViewController) | Contract tests + host binary; **UIKit half not compiled** | Simulator/device |
| Universal Links | App side implemented, server serves AASA | API tests; routing simulated; **not compiled** | Paid team + deployed AASA + device |
| Copy / manual code fallback | Always available | Auto | — |
| Haptics | `Input.vibrate_handheld` via LFPlatform | — | Device |

## 4. Native integrations (`ios/loopfactory-native`)

A **GDExtension** (godot-cpp `godot-4.5-stable`) exposing the Engine singleton `LoopFactoryIOS`.
The Godot-facing class is plain C++. Everything UIKit lives behind `src/lf_bridge.h` in
`src/lf_bridge_ios.mm` (Objective-C++, ARC). Godot's native interface is C/C++, so a Swift layer
would only add a bridging header without adding capability. The bridge uses only public Apple APIs.

| Feature | How |
|---|---|
| Share text / URL / image / image + text | `UIActivityViewController` with a file URL (copied to `tmp/lf-share/`, copies older than 1 h pruned) and the text. Presented on the main thread from the top-most view controller; one sheet at a time; iPad popover anchored bottom-centre (the app is iPhone-only, this just prevents a crash if that ever changes). Missing, unreadable or undecodable files → `invalid_file`, before anything is shown. |
| Sheet result | `completionWithItemsHandler` → `share_finished(result, activity_type)`, emitted deferred into Godot. |
| Universal Links | Godot 4.5.1's `GDTApplicationDelegate` forwards `application:continueUserActivity:restorationHandler:` to registered services; confirmed by inspecting the symbols of `libgodot.ios.release.xcframework`. The module registers its service through `+addService:` (looked up by name at runtime, so a different Godot version only disables links). Registration happens at `UIApplicationDidFinishLaunchingNotification` from `+load`, also reading a cold-start activity from the launch options, and again at extension init. Only `https` URLs are kept; the latest link wins and is consumed once. `launch_uri_received` signals a running app. |
| Keychain | Generic password, service `<bundle id>.auth`, `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`; availability probed with a throwaway item before use. |
| Reduce Motion | `UIAccessibilityIsReduceMotionEnabled()`. |
| Versioning | `apiVersion()`. The GDScript adapter ignores a module older than it expects. |

**Modularity:** the extension is installed into the project (`apps/game/native/ios/`) only for
the duration of a `scripts/build-ios.sh --native` export and removed afterwards. Desktop and
Android builds never see it, and Android presets also exclude `native/*`. Without it, iOS builds
use the fallback.

**What was compiled and tested here:** the C++/godot-cpp half, built for Linux with a stub bridge
(`LF_STUB_BRIDGE`, never shipped) and loaded into Godot 4.5.1 by `scripts/ios/test-native-stub.sh`
(33 checks: registration, every bound method and signal, deferred signal delivery, adapter
selection, share result codes, link queue, UTF-8 Keychain round trip, Game save without the token).
Running the real binary found two bugs that the fake-based tests could not reveal, both fixed:
an infinite recursion in the GDScript adapter's availability check, and a crash **at quit**: a
free lambda (the share-card "sheet closed" handler) connected to the adapter that `LFPlatform`
keeps in a static var outlived the script runtime and corrupted the heap during engine shutdown.
That second one reproduces without any extension on Godot 4.3 and 4.5.1, and would have affected
Android too, because its chooser never reports a close and the handler stayed connected. The
handler is now bound to the Analytics node and only connected where a close event exists (iOS);
`ios_ui_tests` checks no handler is left behind. **The Objective-C++ half has not been compiled.**

## 5. Universal Links

| Piece | Status |
|---|---|
| Link format | `https://<host>/c/<CODE>` (same as Android App Links and the landing page) |
| Server | `GET /.well-known/apple-app-site-association` and `/apple-app-site-association`: `application/json`, no redirect, `{"applinks":{"details":[{"appIDs":[...],"components":[{"/":"/c/*"}]}]}}`. Served only when `IOS_APP_IDS=<TEAM_ID>.<bundle id>` is set; malformed or placeholder team IDs stop the API at startup. 3 API tests. |
| Entitlement | `com.apple.developer.associated-domains = [applinks:<LF_APP_LINK_HOST>]`, added by `build-ios.sh` only when a host is configured. The export check verifies it is exactly that, or absent. |
| App | Native capture (§4) → `LFPlatform` → `main.gd` routing: cold start (splash consumes), backgrounded (resume poll), foreground (signal). Same code again → reopened without stacking; consecutive links → latest; invalid → message, no request; offline → code kept for the next online launch. Simulated in `ios_ui_tests.gd`. Manual code entry stays. |
| Verified end to end | **No.** Needs a paid team, the AASA on the real host, a signed build and an iPhone ([runbook §5](IOS_BUILD_RUNBOOK.md#5-universal-links-paid-programme)). A free Personal Team cannot use Associated Domains. |

## 6. Storage, identity and networking

* Saves: unchanged `user://save.json`, crash-safe. On iOS `user://` is inside the app container
  (included in the device's iCloud/Finder backup; not visible in Files).
* **Refresh token (secure-storage abstraction `LFSecureTokens`):** where `LFPlatform` reports
  secure storage (iOS + native module), the token is written to the Keychain, **read back and
  compared**, and only then left out of the save (`auth.refreshTokenStore = "keychain"`). On write
  or read-back failure it stays in the file, so an identity is never lost for secrecy. Plaintext
  tokens from older saves migrate on the next save. Android, desktop and iOS without the module are
  unchanged (token in the save). **No Android identity is migrated or deleted.**
* **Reinstall:** a fresh install (no save file) deletes any Keychain token left by an earlier
  install. A reinstalled app is a new guest with no progress, on iOS as on Android. **Progress is
  not restorable after reinstall**, because account linking (Sign in with Apple/Google) is not
  shipped. The profile screen already says so.
* Device restore from backup: the save comes back, but a this-device-only Keychain token does not.
  The game then records `secure_token/token_missing`, creates a new guest and replays the local
  progress to it (existing behaviour for a lost identity).
* Networking: unchanged `Net` (single-flight auth, transient vs revoked, offline queue). Release
  configs are HTTPS only, and ATS enforces the same on iOS.

## 7. Lifecycle, audio, accessibility

* `NOTIFICATION_APPLICATION_PAUSED` saves immediately, as before. `NOTIFICATION_OS_MEMORY_WARNING`
  now saves and records a `memory_warning` diagnostic, because iOS can terminate a backgrounded app
  without another callback.
* `NOTIFICATION_APPLICATION_RESUMED` checks for a pending link (both platforms).
* Audio session: `audio/general/ios/session_category = Ambient` and `mix_with_others = true`. The
  game is silent with the ring/silent switch on and doesn't stop the player's music.
* Home indicator auto-hidden, status bar hidden, edge swipe needs a second swipe (no accidental exits
  while dragging near the bottom).
* Reduce Motion: seeded once from the iOS setting at first launch; the in-game toggle wins afterwards.

## 8. Privacy and App Store preparation (not a submission)

| Item | State |
|---|---|
| Tracking | None. No IDFA, no App Tracking Transparency prompt (nothing would require it), `NSPrivacyTracking = false`. |
| Analytics | Opt-in after the first completed puzzle (unchanged). Install-scoped id, not linked to the guest account. |
| Crash diagnostics | Local, scrubbed ring buffer; sent only as consented analytics events. No crash SDK. |
| Third-party SDKs | None in the iOS app (Godot engine only). |
| Privacy manifest (`PrivacyInfo.xcprivacy`, from the preset) | User ID (guest id; linked; app functionality) · Gameplay content (scores, replays; linked; app functionality) · Other user content (display name; linked; app functionality) · Product interaction (consented analytics; not linked; analytics). Godot adds its required-reason API entries (file timestamp, boot time, disk space). |
| App Privacy "nutrition label" | Use the four types above, all "not used for tracking". Data deletion: Settings → Delete my data deletes the server account and local data (and the Keychain token). Data export is available in-app. |
| User-generated content | Display names (server-side moderation list) and challenge codes. No free text is shown to others beyond names. |
| Account deletion (Guideline 5.1.1(v)) | In-app deletion exists and works for guest accounts. |
| Sign in with Apple (Guideline 4.8) | Not needed today: no third-party sign-in is offered. If Google sign-in is added for account linking, Sign in with Apple (or an equivalent) must be offered too; the backend already verifies Apple ID tokens. |
| Encryption export | HTTPS only → `ITSAppUsesNonExemptEncryption = false` (from the template). |
| Permissions | Only "add to Photos", asked by iOS when the player chooses Save Image. Development builds also ask for Local Network. |

## 9. Build workflow

`scripts/build-ios.sh <env> [export|simulator|device|archive] [--native] [--release]`, step by step:

1. Check prerequisites: Godot 4.5.x, iOS template, Xcode and SDK. Missing macOS/Xcode for a
   compile step → **exit 2 (BLOCKED)**.
2. Write and validate the client config. Release environments refuse loopback, private,
   placeholder and non-HTTPS URLs.
3. `--native`: build the extension for device and simulator, debug and release, and assemble
   `.framework`/`.xcframework`.
4. Patch the preset temporarily (restored on exit). Every override is verified (see the fix below).
5. Run the Godot export → `apps/game/build/ios/<env>/LoopFactory.xcodeproj` + `.pck`.
6. Run `scripts/ios/check-ios-export.py`: the PCK's packaged config is byte-identical to the
   validated one, with no tests or editor files; it also checks Info.plist, entitlements, pbxproj,
   the opaque icon and the native module.
7. Run `xcodebuild` for the Simulator (unsigned; install and launch), a device (automatic signing),
   or an archive plus a development `.ipa`.
8. Logs go to `build/ios/<env>/logs/`.

**Results here (Linux):** `development export` passed (26 checks). `staging export` refused the
committed placeholder config. With real HTTPS values (the existing Render API host, used only
as validation input) it passed 27 checks, including `applinks:` and no local networking.
`development device` → exit 2 BLOCKED. **No `.app`, `.ipa` or simulator run was produced, and
none is claimed.**

CI (`.github/workflows/ci.yml`): `ios-export` (Linux: export + validation + host native binding
test) on every PR, and `ios-simulator` (macOS runner: `--native` simulator build and launch) on
demand via `workflow_dispatch`. **Both are new and have not run yet.**

## 10. Android-facing changes

| Change | Effect on Android |
|---|---|
| `LFShare` now calls `LFPlatform` → `LFAndroidAdapter` | Same plugin, same `share(text, absPath, mime, title)` / `consumeLaunchUri()` calls. Verified by `platform_tests` and the existing beta share tests (173 checks, unchanged). |
| Links checked on every resume | **New on Android too:** an App Link delivered to a running activity is now routed (it was only read at launch). Uses the same plugin method. |
| `share_image` validates the file first | A missing or non-image file is `invalid_file` (→ copy-text fallback) instead of a plugin failure. |
| Settings URLs via `LFPlatform.open_external_url` | Only `https:`/`mailto:` URLs reach the OS (release config already guaranteed https); a failure now shows the URL. |
| Haptics via `LFPlatform.vibrate` | Same `Input.vibrate_handheld` call on phones. |
| Memory-warning save | Also applies wherever Godot delivers `NOTIFICATION_OS_MEMORY_WARNING`; not verified on Android. |
| `LFSecureTokens` | Android has no secure backend here, so the save is written **exactly as before** (tested). |
| Analytics `share_sheet_closed`, diagnostics `secure_token`/`memory_warning`/`link` | Additive; never emitted by Android's plugin except `link` (invalid link). |
| `scripts/build-android.sh` `set_preset` | **Bug fix:** the helper never matched `[preset.N.options]`, so `LF_BUILD` (version code) and `LF_VERSION_NAME` were silently ignored for release/AAB builds. Now applied and verified. |
| Android presets exclude `native/*` | No effect (the folder exists only during iOS native exports). |
| Debug APK | Rebuilt with Godot 4.5.1 after these changes (see §11). |

## 11. Test results (this branch, final run)

| Suite | Godot 4.3 | Godot 4.5.1 |
|---|---|---|
| Engine (vitest) | 46/46 | — (engine is TS) |
| API (real Postgres) | 73/73 (+3 AASA) | — |
| Godot unit | 59 tests / 7,778 assertions | 59 tests / 7,778 assertions |
| Auth (headless) | 32/32 | 32/32 |
| Analytics (headless) | 74/74 | 74/74 |
| **Platform services (new)** | 66/66 | 66/66 |
| UI (5 aspect ratios) | 301/301 | 301/301 |
| Crew UI | 201/201 | 201/201 |
| Beta flows (incl. Android share regression) | 173/173 | 173/173 |
| **iOS UI (new: safe areas, links, lifecycle, share)** | 93/93 | 93/93 |
| E2E client ↔ API | 28/28 | 28/28 |
| **iOS native binding layer (new, host build)** | n/a (4.5 only) | 33/33, clean exit |
| Client config rules | 26/26 | — |
| Platform-refs guard | selftest 14/14, tree clean | — |
| iOS export + validation | n/a | development 26 checks · staging 27 checks · staging with placeholders refused |
| Android debug APK (4.5.1) | n/a | built, packaged config matches, artifact check passed (arm64 16 KB-aligned), 57,459,666 bytes, SHA-256 `d60db117…5dae69`. **Not installed on a device** |
| Typecheck, lint, OpenAPI, levels, fixtures | pass | — |
| `npm audit --omit=dev` | 0 vulnerabilities (full tree: 3 moderate, dev-only, unchanged) | — |

The "4.3" suites run with the repository's default `godot` (4.3). The 4.5.1 column is the iOS and
Android build target.

## 12. Blockers and next steps

| Blocker | Who / what |
|---|---|
| Compile, Simulator and iPhone runs | A Mac with Xcode 16.4+ and Godot 4.5.1: `scripts/build-ios.sh development simulator --native`, then `device` ([runbook](IOS_BUILD_RUNBOOK.md)). Alternatively run the `ios-simulator` CI job (workflow_dispatch). |
| The Objective-C++ bridge is uncompiled | First Mac build. Expect possible small compile fixes. |
| Universal Links end to end | Paid Apple Developer team, `IOS_APP_IDS` on the deployed API, `LF_APP_LINK_HOST`, a device. |
| Staging/production URLs | Real API host, privacy policy and support pages (the config refuses placeholders). |
| App Store submission (out of scope) | App Store Connect record, privacy label (§8), screenshots, TestFlight. |

Highest-value next 5:
1. Run `scripts/build-ios.sh development simulator --native` on a Mac and fix any compile errors.
2. Install on an iPhone (`device`) and run matrix sections A–E.
3. Deploy the API with `IOS_APP_IDS` and verify Universal Links (matrix G).
4. Verify the share sheet with Messages, Mail and WhatsApp, and Save Image (matrix F).
5. Record results in the matrix log; only then move the verdict to BUILD → DEVICE-TEST READY.
