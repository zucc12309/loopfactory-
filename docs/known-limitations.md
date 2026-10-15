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
* **Unlockable themes and premium packs:** product ids exist server-side, but the client has a
  single (classic) theme and no theme picker or store screen.
* **Friend comparisons:** not implemented (leaderboards are global/weekly/daily only).
* **Weekly challenges:** a weekly leaderboard aggregates daily results; there is no separate
  weekly puzzle.
* **Native share sheet:** "Share" copies the result text to the clipboard; Android/iOS share
  intents need a small plugin.
* **Active puzzle cross-device resume:** synced to the server, but the client only adopts the
  server's active puzzle when it has none locally (conservative by design).
* **Future tile types** (splitter, switch, portal, one-way/timed gate, colour filter) are designed
  for (separate input/output masks) but not implemented.
* **Localisation:** English only; strings are inline in screen scripts.
* **Music:** only synthesised sound effects; no background music.
* The **GDScript solver** runs on the main thread; expert hints/endless generation take tens of
  milliseconds on desktop and should be profiled on a low-end phone (move to a thread if needed).

## Verification gaps
* **No physical-device or emulator testing** (none available). Touch feel, haptics, audio output,
  lifecycle events (backgrounding, low memory) and frame rate on mid-range Android are untested.
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
