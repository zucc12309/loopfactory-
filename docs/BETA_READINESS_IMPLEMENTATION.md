# Beta readiness: implementation report

Branch `claude/android-beta-readiness`, based on `claude/interdimensional-crew` at
`ba6859ca42d5ff55470782121cfbdecf6a379b45` (the audited commit; no newer Crew commits existed).
The older `claude/loop-factory-build` branch was used only for reference. Nothing was merged
into `main`.

Report date: 2026-10-15. Everything below was run in this repository's Linux container.
**Nothing was run on an Android phone or emulator.** None was available, the container's `adb`
is a stub, and the Android SDK platform packages can't be downloaded here (`dl.google.com` is
blocked by the environment's network policy).

> **Missing audit documents.** `docs/PRODUCTION_GROWTH_AUDIT.md` and the second-branch audit
> report aren't in any branch of the repository, and there is no `audit-evidence/` folder. Each
> finding below was taken from the task brief and checked against the source before it was
> changed. Where a test reproduced the defect on the original code, the matrix says so.

## A. Executive summary

The game's fundamentals were fixed, not extended. No new levels, mechanics, characters or worlds
were added.

* **Identity and data integrity (server and client).**
  * Concurrent token refreshes no longer revoke the session.
  * A refresh response lost after the server rotated the token can be recovered.
  * Temporary failures (offline, timeout, 429, 5xx) never replace a player's guest identity.
  * Best scores, daily results and friend-challenge results can't regress or report rolled-back
    writes under concurrency.
  * Nine new real-Postgres concurrency tests fail on the original code and pass now.
* **Solver honesty.**
  * A result from a search that ran out of budget is labelled `feasible` (upper bound), never
    "optimal".
  * Hints say exactly why they have nothing to show.
  * Both engines agree on every failure path.
* **First-play comprehension.**
  * Reverse rotation is taught on c08, the first level whose par needs it, with an accessible
    ↺ toggle.
  * Analytics consent now appears only after the first delivery.
* **Measurement you can trust.**
  * Consent-anchored cohort events, with no backfill.
  * Per-event IDs so the provider can drop duplicates, and session continuity across restarts.
  * A scrubbed diagnostics boundary.
  * A consented-only persistent event queue that is wiped on opt-out.
* **Android distribution.** Measured, not assumed:
  * Godot 4.3's templates can't meet Google Play's rules (4 KB-aligned native libraries,
    target API 34).
  * The Android build target moves to **Godot 4.5.1**. Every test suite and the E2E test pass
    on both 4.3 and 4.5.1.
  * The build pipeline refuses unsafe release configs and re-checks the config packaged inside
    the artifact.
  * A debug APK was produced. A signed release AAB was **not**: it needs the Android SDK
    platform, a real HTTPS host and the upload key.
* **Sharing.**
  * Share analytics no longer overclaim.
  * Challenge codes are validated before any request, and offline/expired/invalid cases are
    explained.
  * App Link verification (`assetlinks.json`) is served once fingerprints are configured.
  * A native share/App Link Android plugin is written but **not compiled or device-tested**.
* **Security and privacy.**
  * Rate limits are NAT-safe and honestly described as per-process.
  * The dev-only critical/high advisories are fixed.
  * Complete local deletion removes every residual file.
  * The server export covers every data category.
* **Accessibility.**
  * Keyboard/D-pad focus navigation and accessible names.
  * An 88 px dismiss target on Captain Naps' speech bubble.
  * The account-link button that led nowhere is removed.

**Verdict: READY FOR INTERNAL DEVICE TESTING** (see section 6 of the final summary and G below).

## B. Audit issue resolution matrix

| ID | Status | Files | Tests | Remaining risk |
|---|---|---|---|---|
| B-BUILD-1 Reset after zero-move failure | FIXED (fix already on Crew; verified, not duplicated) | `apps/game/scripts/ui/screens/play.gd` (`_reset` → `_after_edit`) | `beta_ui_tests` Reset section: zero moves, one move, undo-to-zero, repeated reset, each also under reduced motion, plus no progress written and a 3-star solve afterwards (62 checks) | None known |
| 1.3 Presentation variants | FIXED (verified equivalent) | `play.gd`, `LFFlags` | `beta_ui_tests`: hybrid / minimal / full give the same level, par, result, ticks, best, stars, save keys, sync ops, controls and symbols (20 checks); Crew UI determinism tests | Which presentation is better is unmeasured |
| R3 Guest identity continuity | FIXED | `apps/game/scripts/core/net.gd`, `services/api/src/services/tokens.ts`, migration `20261016090000_refresh_token_successor` | `tests_e2e/auth_tests.gd` (32 checks: 2 and 5 concurrent calls share one refresh, 429, 5xx, offline then reconnect, lost response, restart during refresh, revoked unlinked/linked, offline campaign); API `concurrency.test.ts` (lost-response recovery, theft still detected, grace window, grace off, 5 concurrent rotations leave exactly one live token) | Restart **more than 120 s** after a lost refresh response: an unlinked guest gets a new guest account. Local progress is kept and re-sent with replays (verified), but server-side history belongs to the old ID (kept in `previousPlayerIds`) |
| R4 Concurrent score updates | FIXED | `services/api/src/db.ts` (`lockedTransaction`), `leaderboards.ts`, `progress.ts`, `friends.ts` | `concurrency.test.ts`: racing better and worse writes, simultaneous first writes, duplicate ops, reversed order, aggregate under contention, parallel friend attempts, rollback and bounded retry. **9 tests across R3/R4/B3 fail on the original code** | Per-player advisory locks serialise one player's writes. That's fine at beta scale; measure under load before a large launch |
| B3 Daily submission results | FIXED | `services/api/src/services/daily.ts` | Concurrent same ID stored once and answered from the committed row; duplicate returns stored (not resent) result; cross-date ID reuse → 409 | None known |
| R5 Recovery and reinstall safety | PARTIALLY FIXED | `net.gd` (`link_identity`), `settings.gd`, `profile.gd` | E2E: link, reinstall, explicit-confirmation switch, progress merged and verified (7 checks); `beta_ui_tests`: no dead link button, honest copy | **No sign-in plugin**, so guests can't restore after uninstall. The UI says so. Merge rules are defined (below) |
| G1 Reverse rotation before c08 | FIXED | `play.gd`, `board_view.gd`, `game_state.gd` | `beta_ui_tests` (cue tile, copy, both presentations, lesson ends on ↺, no repeat, toggle via real pointer input, long-press still works, reduced motion, old saves, players past c09) | Discoverability on a phone is untested |
| G2 Bounded solver optimality | FIXED | `packages/engine/src/solver.ts`, `apps/game/scripts/engine/solver.gd` | Engine tests: audit reproducer (expert seed 2 at 80 nodes → `feasible` 21; full search `solved` 18), all 36 pars proven, hint outcomes; parity outcome fixtures | Generator output unchanged across 6,000 seeds, but daily seeds outside that sample weren't enumerated (the generator only accepts `solved`, i.e. proven, pars) |
| G3 Hint failure copy | FIXED | `play.gd` (`HINT_COPY`, `hint_outcome`) | `beta_ui_tests`: real hint, solved board, exhausted search (retries deeper), non-accusatory unsolvable copy | None known |
| G4 Negative-path parity | FIXED | `scripts/build-parity-fixtures.ts`, `apps/game/tests/test_parity.gd` | Fixtures for wrong destination, deadlock, loop, timeout, off-board, disconnected, queued success/failure, conflicting arrivals, 5 solver statuses, 6 invalid-move cases. Godot matches on all of them | No mismatches were found, so no rules changed |
| G5 Feedback and Reset | FIXED (verified) | — | Reset suite above; existing UI tests (rapid input, celebration skip, Run/Stop ×12) | Feel on a phone is unverified |
| U1 Consent timing | FIXED | `main.gd` (`consent_due`, `ask_consent`), `home.gd`, `play.gd` | `beta_ui_tests`: none on fresh Home, first puzzle, celebration or win card; asked at the Next transition; accept, decline, asked once, Settings toggle kept (14 checks); screenshot `docs/screenshots/beta-consent.png` | None known |
| R7 Cohort measurement | FIXED (client); not run against a real provider | `analytics.gd` | `tests_e2e/analytics_tests.gd` (74 checks: no consent, consent after win with no backfill, decline, offline then reconnect with the same UUIDs, restart, background/resume, revocation wipe, one-time events across restarts) | No analytics project exists. The funnel only covers players who consent, and steps before consent (first rotation/run/delivery) are unobservable for most players **by design** |
| R8 Crash/error diagnostics | PARTIALLY FIXED | `diagnostics.gd`, `game.gd`, `net.gd`, `main.gd`, `settings.gd` | `analytics_tests`: scrubbing, recoverable/fatal, consent gating, once-per-session network errors, monitoring status | **Native crash capture: not implemented** (no SDK or credentials; Godot 4.3 has no hook). No crash-free-session rate is claimed |
| R1 Environment configuration | FIXED | `config/client/*.json`, `scripts/client-config.ts`, `LFReleaseConfig` | 26 self-test checks (23 shared cases, run in TS and in GDScript, plus template refusal); staging build refused with placeholders, nothing written | Real staging/production values don't exist yet |
| R2 Reproducible Android builds | PARTIALLY FIXED | `scripts/build-android.sh`, `scripts/android/check-artifact.py`, `export_presets.cfg` ("Android AAB": Gradle, min 24, target 36), CI | Debug APK built with Godot 4.5.1, config inspected, ELF alignment checked | **Release AAB not built** (no Android SDK platform here, no HTTPS host, no upload key). **Not installed on a device.** Play acceptance untested |
| R2.1 Device test matrix | DEFERRED (matrix written) | Section F | — | No device results exist |
| R6 Native share sheet | PARTIALLY FIXED | `share.gd`, `share_card.gd`, `android/share-plugin`, `addons/loopfactory_share` | Fallback, plugin-opened and plugin-failure paths (fake plugin); Java type-checks against API stubs | **The plugin hasn't been compiled with the Android SDK or run on a device.** This build has no native share: Copy text only on phones |
| R6.1 Same-puzzle challenge journey | PARTIALLY FIXED | `share.gd`, `challenge.gd`, `main.gd`, `net.gd`, `app.ts` (`assetlinks.json`), `friends.ts` (landing page) | Link parsing and 8 invalid inputs; invalid/offline/unreachable states; pending code reopened; assetlinks with and without fingerprints; landing page | Installed-app routing needs the plugin and a verified domain. Deferred (post-install) deep linking isn't possible: the landing page shows the code for manual entry |
| M1 Sharing analytics | FIXED | `analytics.gd`, `share_card.gd`, `challenge.gd`, `play.gd` | `beta_ui_tests` share section; `test_upgrade` taxonomy | Whether a recipient received anything is not observable and isn't claimed |
| B5 NAT-safe rate limiting | FIXED | `middleware/rateLimit.ts`, `app.ts`, `routes/index.ts` | `ratelimit.test.ts` (6): 40 players × 20 requests from one IP aren't throttled (**fails on the original limiter**); per-player and anonymous caps; guest burst; per-session refresh | Guest creation is still per IP (no other signal exists). The hourly cap is 200 |
| B6 Multi-worker limiter | FIXED for the single-instance beta (documented) | `rateLimit.ts`, `server.ts` (startup log) | Restart resets counters | Multiple instances multiply the limits. Add a shared store before scaling out |
| S1 Dependency advisories | FIXED (critical/high); 3 moderate accepted | `package.json`, `package-lock.json` | `npm audit --omit=dev`: 0. Full audit: 3 moderate | uuid < 11.1.1 via autocannon → hyperid, used only by the load-test tool; unreachable from the app |
| L1 Privacy deletion/export | FIXED | `game.gd` (`wipe_local`, `residual_files`), `save_store.gd`, `settings.gd`, `privacy.ts` | `analytics_tests` deletion (save, backup, quarantined copy, queue, diagnostics, export, share images); API export coverage and full erasure | Export on phones uses the share sheet when the plugin exists; without it the JSON goes to the clipboard |
| U2 Accessibility | PARTIALLY FIXED | `style.gd`, `icon_button.gd`, `main.gd`, `home.gd`, `levels.gd`, `settings.gd`, `profile.gd` | `beta_ui_tests` (focus, names, 88 px target, no dead button) | **TalkBack untested.** Godot ignores Android font scaling. The board isn't exposed to screen readers |
| Phase 8 UI polish | DEFERRED except as noted | Crew readability test (16/24/32/48 px, symbols distinct) | `crew_ui_tests` +80 checks | Home "next reward", Worlds milestone clarity and conveyor-direction emphasis are hypotheses for usability testing |

## C. Implementation details

### Authentication

* **Server.**
  * Each rotation records its successor (`replaced_by_id`). The claim, the successor and the
    link commit in one transaction.
  * A token presented again within `REFRESH_REUSE_GRACE_SECONDS` (default 120, max 600, 0
    disables) while its successor is unused is treated as a lost response:
    * the unused successor is revoked;
    * a new one is issued under a row lock;
    * only one live successor ever exists.
  * Reuse after the successor was used still revokes the whole family, so theft is still
    detected.
* **Client (`net.gd`).**
  * Single-flight `_ensure_token()`: concurrent callers wait for one refresh.
  * Errors are classified as offline, transient (408/429/5xx; two retries with full-jitter
    backoff of 0.4–2.4 s) or revoked.
  * Only a definitive 4xx on an **unlinked** guest creates a new guest. Its old ID is recorded
    and local progress is re-sent **with** stored replays, so results arrive verified.
  * A linked account is never silently swapped.
  * Rotated tokens are saved with `save_now()` before use.
* **Account merge rules (defined for when a sign-in plugin exists; `Net.link_identity`):**
  * `linked`: nothing moves.
  * `switched` needs explicit confirmation (`onConflict: switch`).
    * The device adopts the restored account and keeps the old guest ID for support.
    * Local completions are re-sent (the server keeps the minimum, so nothing regresses).
    * Looks re-derive from progress.
    * Settings are last-writer-wins.

### Database

* **`lockedTransaction(db, keys, fn)`:**
  * takes a sorted per-key `pg_advisory_xact_lock` (e.g. `player:<id>`);
  * retries serialization failures and deadlocks up to 3 times with jitter.
* **Leaderboard minimum.** A single `INSERT … ON CONFLICT … DO UPDATE … WHERE score >
  EXCLUDED.score`, with `clock_timestamp()` as the tie-breaker.
* **Unique-violation handling.** `isUniqueViolation(e, fields)` matches only the named
  constraint. Daily duplicates are answered from the committed row; anything else re-throws and
  is never reported as accepted.
* **Migration.** `20261016090000_refresh_token_successor` adds one nullable column, so it's
  backward compatible.

### Solver

* **Statuses:**
  * `solved` (proven optimal: the search finished, or found a 0-cost solution);
  * `feasible` (verified solution, budget ran out; `minCost` is an upper bound);
  * `budget_exceeded`;
  * `unsolvable`.
* An `optimal` flag accompanies every result.
* `hintOutcome` / `hint_outcome` return `hint | solved | exhausted | unsolvable`, and the hint
  carries `optimal`.
* Consumers that set pars (generator, `build-levels`) accept only `solved`.

### Onboarding

* **c08 lesson.** c08's par needs one ↺ on tile 7. On c08, until the player has turned any belt
  counter-clockwise or has finished c09:
  * the banner reads "Turn it back — Tap to turn ↻. Hold to turn ↺.";
  * the board shows a press-and-hold ring (static under reduced motion).
* **Early levels.** Three clockwise taps in a row on one belt earn a one-time tip.
* **"Turn ↺" toggle** (from c08 on, every non-campaign puzzle): taps turn counter-clockwise and
  holds turn clockwise. It's an accessible alternative to long-press.
* Pars and rules are unchanged.

### Analytics

* **Schema 2.**
* **Common properties:** `schema`, `app_version`, `build`, `environment`, `platform`,
  `os_major`, `device_class` (phone/tablet/desktop) and `session_id`.
* **Cohort anchor:** `consent_granted` (`levels_completed`, `sessions`, `surface`).
* **One-time events:** `first_rotation`, `first_run`, `first_delivery`, `tutorial_start`.
  * They are marked done even without consent, so they're never backfilled.
* **Queue:**
  * persists only while consented;
  * written at most once per frame;
  * deleted (and any in-flight send cancelled) on opt-out.
* **Deduplication:** each event carries a `uuid` the provider can deduplicate on.
* **Sessions:** a relaunch within 30 minutes continues the session (`app_resume` with
  `cold_start`).
* **Funnel for consented cohorts:** see [analytics.md](analytics.md#consented-cohorts).

### Diagnostics

`LFDiagnostics` stores errors in a local ring buffer of 50 (`user://diagnostics.json`).

* **Categories recorded:** `save_failed`, `save_recovered`, `unclean_exit` (fatal proxy),
  `network`, `auth` (once per session), `config`, `share` and `diagnostic_test`.
* **Context:** build, environment and OS major version.
* **Scrubbing:** keys mentioning token, auth, URL, code, player, password or secret are dropped,
  and URLs inside text are redacted.
* **Sending:** only with consent, as `app_error` / `network_error`.
* **Monitoring status:** a staging build with monitoring off or an unsupported provider shows a
  visible warning.
* **Verification:** in Settings, tap the version line 7 times; a toast confirms the record.
  Then check `diagnostics` in Export my data, or `app_error` in the provider.

### Android

* **Engine target: Godot 4.5.1.** Measurements on the same project:

| | Godot 4.3 templates | Godot 4.5.1 templates |
|---|---|---|
| arm64-v8a ELF LOAD alignment | 4 KB (2**12), so **not** 16 KB-ready | **16 KB** (2**14) |
| armeabi-v7a | 4 KB | 4 KB (32-bit is outside the 16 KB rule) |
| Default compile/target SDK | 34 | 35 (Gradle preset sets **36**) |
| Our test suites | all pass | **all pass** (unit 59 / 7,771 assertions, auth 32, analytics 74, UI 301, Crew UI 201, Beta UI 171, E2E 28; run before `9bb106f`) |

* **Google Play rules**, read from developer.android.com on 2026-10-15:
  * New apps and app updates must target **API 36** from 2026-08-31 (extension possible to
    2026-11-01).
  * Apps targeting API 35+ must support 16 KB pages on 64-bit devices. Updates without it are
    blocked from 2027-02-01.
* **Migration risks still to verify on devices:**
  * Targeting 35+ forces edge-to-edge drawing. Safe-area handling exists (`main.safe_margins()`)
    but hasn't been seen on a gesture-navigation phone.
  * Targeting 36 ignores orientation locks on large screens (600 dp and wider), so tablets may
    rotate.
  * The 4.5 editor writes `.uid` files; they're committed.
* **Pipeline (`scripts/build-android.sh debug | release <env> | aab <env>`):**
  * writes a validated config, refusing loopback, private, `.example` or placeholder hosts,
    non-HTTPS URLs, missing privacy/support URLs, a missing build number, test switches and
    secret-like keys;
  * sets the version code and name;
  * exports;
  * re-reads `assets/config/client.json` from **inside** the artifact and requires it to match
    byte for byte;
  * runs `check-artifact.py` (ABIs, 16 KB ELF alignment, no test or editor files);
  * prints size and SHA-256;
  * refuses Godot 4.3 for release;
  * names the exact missing SDK, template or key for an AAB.
* **Signing.**
  * Debug uses the editor-settings debug keystore.
  * Release and AAB read `GODOT_ANDROID_KEYSTORE_RELEASE_PATH`, `_USER` and `_PASSWORD` from the
    environment. Keys never enter Git (`*.keystore` and `*.jks` are ignored).
  * Use Play App Signing: Google holds the app signing key; you keep the upload key.
* This container signs with `apksig` (Google's library) through a small CLI shim
  (`scripts/android/setup-sandbox-signer.sh`), because the real build-tools couldn't be
  downloaded. CI uses the real `apksigner` and runs `zipalign -c -P 16` with build-tools 35.

### Sharing

* **`LFShare`** wraps the `LoopFactoryShare` plugin:
  * it copies the file to `cache/shared/`, exposes it through a FileProvider `content://` URI,
    sets `FLAG_GRANT_READ_URI_PERMISSION` plus ClipData, and opens `Intent.createChooser`;
  * only "chooser opened" is tracked.
* **Without the plugin:**
  * phones show **Copy text** only, with no fake "Save image" pointing into private storage;
  * desktop saves to Pictures.
* **Events:** `share_card_created`, `share_text_copied`, `share_image_saved` and
  `share_sheet_opened` replace `share_completed`, which counted a clipboard copy or an unknown
  plugin call as a completed share.
* **Challenges:**
  * Codes are validated against the 8-character alphabet before any request. `get_challenge_result`
    distinguishes `invalid`, `not_found` (expired or unknown), `offline` and `error`.
  * An offline code is kept and reopened at the next launch.
  * Invites always carry the code, plus an `https://<appLinks.host>/c/CODE` link when configured.
* **Server:**
  * `/.well-known/assetlinks.json` is served only when `ANDROID_CERT_SHA256` is set (format
    validated at startup).
  * The landing page explains that store installs don't carry the link and shows the code.

### Privacy

* **Complete local deletion** (Delete account & data) removes:
  * the save, `.tmp`, `.bak` and all `.corrupt` copies;
  * the analytics queue, diagnostics and the export file;
  * share images.
* Ordinary saves still keep `.bak`.
* **Data export:**
  * goes to the share sheet when available, otherwise to Documents on desktop or to the
    clipboard;
  * a private `user://` path is never shown;
  * the server export adds identity email, session metadata and the sync log;
  * credentials are never included.

## D. Verification evidence

Commits on `claude/android-beta-readiness`, oldest first:

| SHA | Change |
|---|---|
| a3c47c1 | API: atomic best-score writes, committed-state daily results, lost-response token recovery |
| 039f1f2 | Client: single-flight auth refresh, guest continuity, recovery boundary |
| adee9ab | Engine: explicit solver outcomes, hint outcomes, negative-path parity |
| 8cb8a01 | Play: reverse-rotation lesson, ↺ toggle, hint copy, Reset regressions |
| 73ab868 | Release config validation and diagnostics boundary |
| 004120e | Consent after first delivery, cohort events, complete local deletion |
| 0b99882 | Native share boundary, challenge links, honest share analytics |
| caee532 | Android: Godot 4.5.1 target, validated release pipeline, artifact inspection |
| 2a25591 | API: NAT-safe rate limits; dev dependency remediation |
| efe4422 | Privacy export coverage; accessibility |
| 8778fe5 | Symbol readability tests; beta flow screenshots |
| 9bb106f | Profile: remove the dead account-link button |

The commit that adds this document follows these.

**Baseline**, re-run on a clean checkout of `ba6859c`: engine 41, API 41, Godot 56 tests /
7,481 assertions, UI 281, Crew UI 121, E2E 21. All passed.

**Final run.** Node 22.22.0, PostgreSQL 16.15, Godot 4.3-stable and 4.5.1-stable. The final
full run (`runall.sh`) ran before `9bb106f` and the documentation. After `9bb106f` the Godot
unit suite (59 / 7,771, 0 failed), the Beta UI suite (173, 0 failed) and the UI suite (301,
0 failed) were re-run.

| Command | Exit | Result |
|---|---|---|
| `npm run typecheck` | 0 | clean |
| `npm run lint` | 0 | clean |
| `npm test -w @loopfactory/engine` | 0 | 46 tests passed (5 files) |
| `npm run levels:check` | 0 | 36 curated levels verified |
| `npm run fixtures:check` | 0 | parity fixtures up to date |
| `npm run openapi -w @loopfactory/api -- --check` | 0 | up to date |
| `npm run build -w @loopfactory/api` | 0 | built |
| `npm test -w @loopfactory/api` (real Postgres) | 0 | 70 tests passed (7 files) |
| `npm run config:check` | 0 | 26 checks, 0 failed |
| `bash scripts/test-game.sh` (Godot 4.3) | 0 | unit 59 tests / 7,771 assertions; auth 32; analytics 74; UI 301; Crew UI 201; Beta UI 171 (173 after `9bb106f`); 0 failed |
| `GODOT=…4.5.1 bash scripts/test-game.sh` | 0 | same counts, 0 failed |
| `bash scripts/e2e.sh` (4.3 and 4.5.1) | 0 | 28 checks, 0 failures each |
| `npm audit --omit=dev` | 0 | 0 vulnerabilities |
| `npm audit` | 1 | 3 moderate (uuid via autocannon, dev-only) |

**Artifact produced:**
`apps/game/build/loopfactory-debug.apk`

* **Command:** `GODOT=<4.5.1> scripts/build-android.sh debug`.
* **Size:** 57,141,334 bytes. Built from `8778fe5`; `9bb106f` only removes a button in
  Profile, so rebuild before installing.
* **SHA-256:** `a752c1eecdb36a2a2ce2012c6cc17549fae6eef9f8e411624e81be78ae234d14`.
* **ABIs:** arm64-v8a and armeabi-v7a; arm64 libraries 16 KB-aligned.
* **Signing:** APK Signature Scheme v2, debug key.
* **Packaged config:** `environment=development`, API `http://127.0.0.1:8080` (the phone itself),
  so online features are unavailable on a device unless rebuilt with `LF_API_BASE_URL`.
* The file is git-ignored and not committed.

Screenshots (desktop GL renderer at 720×1280, not a phone):
`docs/screenshots/beta-reverse-cue.png`, `beta-consent.png`, `beta-challenge-offline.png`.

## E. External setup requirements

| Need | Where | Notes |
|---|---|---|
| Godot **4.5.1** + export templates | developer machine, CI (`GODOT_VERSION`) | 4.3 templates are refused for release |
| Android SDK: `platforms;android-36`, `build-tools;35.0.0`+, `platform-tools`; JDK 17 | developer machine / CI | Needed for the Gradle AAB and the share plugin. Unavailable in this container (`dl.google.com` blocked) |
| Gradle build template | `apps/game/android/build` (Project → Install Android Build Template, from Godot 4.5.1) | Required by the "Android AAB" preset |
| Upload keystore | password manager / CI secret | `GODOT_ANDROID_KEYSTORE_RELEASE_PATH`, `_USER`, `_PASSWORD`. Enrol in Play App Signing |
| HTTPS API host | deployment (`render.yaml`) | `LF_API_BASE_URL`; server `PUBLIC_BASE_URL` |
| Privacy policy URL, support URL | public website | `LF_PRIVACY_POLICY_URL`, `LF_SUPPORT_URL` (release builds fail without them) |
| App Links domain | DNS + API | `LF_APP_LINK_HOST` (client), `-PappLinkHost` (plugin), `ANDROID_CERT_SHA256` (server: Play App Signing certificate SHA-256 plus the upload key for internal builds) |
| Analytics | PostHog (or similar) project | public key only, via `LF_POSTHOG_KEY` |
| Crash capture | a native SDK/plugin (e.g. a Sentry Godot plugin) | not integrated; the local diagnostics boundary is active (`crashReporting.provider: local`) |
| Google/Apple sign-in | OAuth client IDs plus native plugins | for account restore (R5) |
| Play Console | developer account | internal testing track first |

**Build a staging release (once those exist):**

```
export LF_BUILD=3 LF_VERSION_NAME=0.3.0-beta.1 \
  LF_API_BASE_URL=https://api.staging.<your-domain> \
  LF_PRIVACY_POLICY_URL=https://<your-domain>/privacy LF_SUPPORT_URL=https://<your-domain>/support \
  LF_APP_LINK_HOST=play.<your-domain> \
  GODOT=/path/to/Godot_v4.5.1 GODOT_ANDROID_KEYSTORE_RELEASE_PATH=... \
  GODOT_ANDROID_KEYSTORE_RELEASE_USER=upload GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD=...
scripts/build-android.sh aab staging        # Gradle; or `release staging` for a sideloadable APK
bundletool build-apks --bundle apps/game/build/loopfactory-staging.aab --output /tmp/lf.apks   # inspect
```

**Share plugin:**

1. `cd android/share-plugin && gradle assembleRelease -PappLinkHost=play.<your-domain>`
2. Copy the AAR to `apps/game/addons/loopfactory_share/bin/share-plugin-release.aar`.
3. Enable the plugin under Project Settings → Plugins.
4. Export with the Gradle preset.

**Rollback:**

* Play Console: halt the staged rollout, or promote the previous release on the track.
* Clients stay compatible: the API change is additive (one nullable column).
* To roll back the server, deploy the previous image. The migration doesn't need reverting:
  the new column is unused by old code.

## F. Device QA checklist

Run on real phones, and record every row: device model, Android version, build (`version code` and
the SHA-256 above or of the build you install), steps, expected, actual, pass/fail/not tested, evidence (screenshot or
video file name). **No row has been executed yet.**

| # | Area | Device class | Steps | Expected |
|---|---|---|---|---|
| 1 | Install | budget (2–3 GB RAM, Android 10–12) | `adb install loopfactory-debug.apk`; launch | Launches to Home in < 3 s; no crash |
| 2 | Install | mid-range (Android 13–14) | same | same |
| 3 | Install | recent (Android 15–16, 16 KB-page device if available) | same; also confirm with `adb shell getconf PAGE_SIZE` | Launches; no "16 KB" compatibility warning |
| 4 | First play | any | Fresh install → Play c01 → solve → Next | No consent prompt before or over the win card; prompt at level 2; both buttons work |
| 5 | Reverse lesson | any | Reach c08 | Hold cue on the bottom corner; holding turns ↺; cue disappears; doesn't return |
| 6 | ↺ toggle | any | c08+: turn on "Turn ↺", tap a belt | Turns counter-clockwise; one move counted |
| 7 | Reset | any | Run a wrong board with no moves → Reset | Failure banner and highlight clear |
| 8 | Aspect ratios | small (≤ 5.5″, 16:9) and tall (20:9+) | Play c34 (6×7) | Board, banner and buttons fully visible; nothing under the notch or gesture bar |
| 9 | Gesture nav / edge-to-edge | Android 15+ | Swipe-back on Home and Play | Back closes overlays then navigates; content not under system bars |
| 10 | Airplane mode | any | Play 3 levels, endless, offline daily | All playable; progress persists after kill and relaunch |
| 11 | Slow network | throttled 3G | Sync, open daily | UI never blocks; queued completions sync later |
| 12 | Background/resume | any | Home button mid-run; return after 5 s and after 10 min | Run resumes or finishes cleanly; no duplicate session in analytics (consented) |
| 13 | Process death | any | Developer options "Don't keep activities"; background; return | Board restored with moves intact |
| 14 | Low memory | budget | Open several heavy apps, return | Game restores state or restarts cleanly with progress |
| 15 | Audio/haptics | any | Toggle sound, music and vibration | Each independent; subtle levels |
| 16 | Orientation | phone + tablet | Rotate the device | Portrait kept on phones; tablet (≥ 600 dp) behaviour noted (API 36 ignores locks) |
| 17 | Font scaling | any | System font size largest | Note: the game doesn't follow it (known); text still readable |
| 18 | Battery/thermal | budget | 20 min continuous play | No noticeable heat; record battery % used |
| 19 | Share | any | Win → Share → Copy text; paste in a messenger | Text arrives. Native share sheet only in a build that includes the plugin |
| 20 | Share chooser (plugin build) | any | Share → pick WhatsApp, Instagram, Gmail | Image and text received where the target supports them; cancelling returns to the game |
| 21 | Challenge link (plugin build, verified domain) | two phones | A creates a challenge; B taps the link | App opens the same puzzle; uninstalled → landing page with code |
| 22 | Challenge offline | any | Airplane mode → Friends → enter code | "You're offline… we saved the code"; reopened at next online launch |
| 23 | Delete data | any | Settings → Delete account & data (online) | Everything reset; `run-as com.loopfactory.game ls files` shows only a fresh save |
| 24 | TalkBack | any | Enable TalkBack, navigate Home | **Record actual behaviour**; not supported claims until verified |
| 25 | Keyboard/D-pad | Chromebook or BT keyboard | Press arrow keys | Focus ring visible; Enter activates |

## G. Remaining blockers

**Source defects (known):** none open from the audit list.

Engineering gaps that still need work:

* The share/App Link plugin is uncompiled.
* There's no native crash capture.
* No sign-in plugin exists, so there's no account restore.

**Missing credentials:**

* Upload keystore.
* PostHog key.
* OAuth client IDs (Google/Apple).
* `ANDROID_CERT_SHA256` (after Play App Signing enrolment).

**Missing infrastructure:**

* A deployed HTTPS API (staging and production).
* Privacy policy and support pages.
* An App Links domain.
* An Android SDK in CI or on a build machine. The CI file is updated but hasn't run on GitHub
  yet.

**Missing device evidence:**

* Every row in F.
* Frame time on a low-end phone.
* Edge-to-edge and safe-area behaviour on Android 15+.
* 16 KB-page runtime.

**Play Console requirements:**

* Developer account and app record.
* Data safety form (matches docs/privacy-policy.md: no ads ID, optional analytics).
* Content rating, target audience, internal testing track.
* AAB upload acceptance.

**Optional improvements (hypotheses, not blockers):**

* Home "next reward" hint.
* Worlds milestone clarity.
* Conveyor-direction emphasis.
* Following system font scale.
* A shared rate-limit store for multi-instance deployments.

## H. Next 7 days (release-critical only)

1. **Day 1.** Provision a build machine (or a CI runner) with Godot 4.5.1, Android SDK 36 and
   build-tools 35, then install the Gradle template.
   * Build `aab staging` and inspect it with bundletool and `check-artifact.py`.
   * Build the share plugin AAR.
2. **Day 1–2.** Deploy the staging API over HTTPS. Publish the privacy and support pages.
   * Set `PUBLIC_BASE_URL` and `ANDROID_CERT_SHA256`.
   * Build the staging APK and install it on 3 phones (budget, mid-range, recent).
3. **Day 2–4.** Run checklist F on all three phones and record the evidence.
   * Fix anything found, especially edge-to-edge/safe areas and the API 36 orientation
     behaviour.
4. **Day 3.** Create the Play Console app with Play App Signing.
   * Upload the AAB to internal testing.
   * Fill in the data safety and content rating forms.
5. **Day 4–5.** Decide on crash capture: integrate a native SDK, or accept local diagnostics for
   the first beta. Connect the analytics project and verify consented events end to end with the
   7-tap test.
6. **Day 6–7.** Internal testers (10–20) on the internal track. Watch diagnostics and the
   consented funnel. Fix release blockers. Then go to a limited closed beta.
