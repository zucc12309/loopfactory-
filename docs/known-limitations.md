# Known limitations and pending integrations

Everything below is either not implemented or implemented only up to an interface. Nothing here
is represented elsewhere as complete.

## Requires external accounts / credentials (interfaces done, integration pending)
| Item | State |
|---|---|
| Google sign-in / Sign in with Apple | Server verification implemented (JWKS); needs OAuth client ids / bundle ids. **Client** needs native sign-in plugins — the Link button currently explains this. |
| Google Play Billing / StoreKit | Server entitlement model, idempotent verify endpoint, restore and dev verifier done; real store verifiers, refund webhooks and client billing plugins + store UI pending. |
| Rewarded ads | Remote-config flag only (off). No ad SDK integrated. |
| Analytics provider | Consent-gated client adapter with PostHog HTTP batching; needs a project key. Not exercised against a live PostHog project. |
| Crash/error monitoring | Server Sentry adapter (needs DSN + `@sentry/node`). **Client crash reporting is not integrated** (would need the sentry-godot plugin). |
| Production deployment | `render.yaml`, Dockerfile, migration/rollback/backup docs ready. Nothing was deployed (no authorisation to create billable resources). |
| Play Store upload | AAB requires the Gradle build template and Google's Maven access; only APKs were built here. |
| iOS | Export preset and docs only; no macOS/Xcode was available, so no iOS build exists. |

## Product / feature gaps
* **Unlockable themes and premium packs:** product ids exist server-side. The five campaign
  worlds each have their own board palette and are reached through progress, but there is no
  theme picker, no store screen and no purchasable theme.
* **Native share sheet:** the result card PNG and challenge invite are generated. On Android and
  iOS the text goes to the clipboard and the image stays in app storage. `LFShareCard.native_share()`
  is the boundary for a share plugin, and no plugin ships. See [sharing.md](sharing.md).
* **Deep links into the app:** challenge links open a landing page that shows the code. App Links
  and Universal Links (intent filter in a Gradle Android export, `assetlinks.json`,
  `apple-app-site-association`, a launch-URL plugin) are not configured, so players type the code.
* **Video export of replays:** not implemented. The replay screen has a clean view meant for the
  OS screen recorder. There is no automatic zoom.
* **Friends leaderboard:** comparisons are per challenge code (everyone who played it). There is
  no friend graph or contacts import, by design.
* **Weekly challenges:** a weekly leaderboard aggregates daily results. There is no separate
  weekly puzzle pack.
* **Active puzzle cross-device resume:** synced to the server, but the client only adopts the
  server's active puzzle when it has none locally (conservative by design).
* **Replays** are stored on the device only and are not synced.
* **Future tile types** (splitter, switch, portal, one-way/timed gate, colour filter) are
  designed for (separate input/output masks) but not implemented.
* **Localisation:** English only. Strings are inline in screen scripts.
* **Difficulty weights and experiment defaults** are hypotheses. They have not been fitted to
  real player data (no analytics project is connected).
* The **GDScript solver** runs on the main thread. Expert hints and endless generation take tens
  of milliseconds on desktop and should be profiled on a low-end phone (move to a thread if needed).

## Character system (Interdimensional Delivery Crew)
* **Art is v1 procedural vector art**, drawn in code in a consistent direction — not a final
  illustrator pass ([CHARACTER_ART_GUIDE.md](CHARACTER_ART_GUIDE.md)). No image-generation tool
  was available.
* **Mochi never appears on a board:** current levels and the generator use at most three colours.
  A four-colour world needs separate design and solver validation.
* **No new mechanics or extra sci-fi worlds** (portals etc.). Dr. Rix introduces existing mechanics.
* **Equipped looks and crew settings are device-local** (the API's settings schema strips unknown
  keys; unlocks re-derive from synced progress).
* **Localisation:** dialogue supports per-id translation files, but only English ships; roster
  descriptions and UI labels are still inline. No machine translation by design.
* **Effect on retention is unmeasured** — needs the `presentation` experiment with real players.
* Character voice is two tiny synthesised sounds; no voice lines.

## Verification gaps
* **No physical-device or emulator testing** (none available). This includes the character
  system's frame rate, readability, haptics and lifecycle behaviour on budget phones
  ([manual test plan](CHARACTER_TESTING.md#manual-device-tests)). Touch feel, haptics, audio output
  and music mix, lifecycle events (backgrounding, calls, low memory), frame rate and battery on
  mid-range Android are untested. Layout was tested on five aspect ratios in a desktop renderer,
  and render cost was measured on desktop CPU only ([performance.md](performance.md)).
* The **friend-challenge endpoints** have integration and E2E tests but were not included in the
  load test.
* Load tests ran on one shared 4-vCPU VM with the generator co-located (see load-testing.md);
  re-run against staging from a separate machine before launch.
* The Docker image was validated using a registry mirror and the full `node:22-bookworm` base,
  because Docker Hub was rate-limited and Debian mirrors were blocked in this environment. The
  default `node:22-bookworm-slim` + `apt-get install openssl` path is standard but was not
  executed here.
* The sandbox APK signing used a small apksigner-compatible tool on Google's `apksig` library
  (Android SDK downloads were blocked); CI uses the real Android SDK.

## Competitive integrity
* Rankings use server-verified rotation counts only. Completion time is deliberately **not**
  ranked because it cannot be verified. A player using an external solver will reach par —
  ties at par are broken by who submitted first.
* Guest creation is rate limited per IP but not device-attested (Play Integrity / App Attest
  recommended before scaling marketing).
