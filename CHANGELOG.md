# Changelog

All notable changes to this project are documented here (format: Keep a Changelog, versions: SemVer).

## [Unreleased] — iOS readiness

See [docs/IOS_READINESS.md](docs/IOS_READINESS.md). Verdict: iOS source ready (not yet compiled on a Mac).

### Added
- `LFPlatform` cross-platform services (`apps/game/scripts/platform/`): Android, iOS and safe
  fallback adapters for sharing, links, external URLs, haptics, secure storage and Reduce Motion.
- `LoopFactoryIOS` GDExtension (`ios/loopfactory-native`): UIActivityViewController sharing,
  Universal Links through Godot 4.5's app-delegate services, Keychain, Reduce Motion. The
  binding layer is compiled and tested on the host; the UIKit half still needs a Mac.
- Refresh token in the iOS Keychain (`LFSecureTokens`), with read-back verification, migration and
  reinstall handling; Android unchanged.
- Links delivered to a running app are routed on both platforms (signal + resume poll).
- API: `apple-app-site-association` (`IOS_APP_IDS`).
- `scripts/build-ios.sh`, `scripts/ios/check-ios-export.py`, `scripts/ios/test-native-stub.sh`,
  `scripts/check-platform-refs.py`; CI jobs `ios-export` and on-demand `ios-simulator`.
- Tests: `tests_e2e/platform_tests.gd`, `tests_ui/ios_ui_tests.gd` (4 iPhone safe-area
  geometries), `tests_e2e/ios_native_binding_tests.gd`, AASA API tests.
- Docs: IOS_READINESS, IOS_BUILD_RUNBOOK, IOS_DEVICE_TEST_MATRIX.

### Changed
- iOS preset rebuilt for Godot 4.5.1 (iOS 15.0+, opaque icon, purpose strings incl. add-to-Photos,
  privacy manifest data types); iOS audio session Ambient + mix.
- Memory warnings save immediately.

### Fixed
- `build-android.sh` / `build-ios.sh` `set_preset` never applied options (the Android version code
  from `LF_BUILD` was silently ignored for release/AAB builds).

## [Unreleased] — Android beta readiness

See [docs/BETA_READINESS_IMPLEMENTATION.md](docs/BETA_READINESS_IMPLEMENTATION.md).

### Fixed
- Concurrent best-score writes (progress, daily, weekly/global aggregates, friend attempts) can no
  longer regress or be lost as false duplicates; daily duplicates answer from committed state;
  submission ids reused across dates are refused.
- Concurrent token refreshes and temporary failures (offline, 429, 5xx) no longer replace the guest
  identity; a refresh response lost after rotation is recoverable within 120 s.
- A budget-limited solver result is reported as `feasible`, never as optimal; hint copy says
  whether the board is solved, the search ran out, or there is no route.
- Rate limits no longer throttle players who share a carrier-NAT IP.
- Complete local deletion removes backups, quarantined saves, analytics queue, diagnostics,
  exports and share images; data export no longer shows a private file path.
- The Profile "Link account" button that led nowhere is removed.
- `scripts/e2e.sh` no longer passes when the test script fails to compile.

### Added
- Reverse rotation taught on c08 (hold cue) and a "Turn ↺" toggle as a long-press alternative.
- Consent asked after the first delivery; consent-anchored cohort events with schema version,
  per-event uuid, consented-only persistent queue and session continuity.
- Diagnostics boundary (scrubbed, local + consented); staging config/monitoring warning.
- Validated client config per environment and a release pipeline that refuses unsafe configs and
  inspects the config and native-library alignment inside the artifact.
- Native share / App Link Android plugin (source; not compiled here), `assetlinks.json`, challenge
  code validation and offline handling; precise share events replace `share_completed`.
- Keyboard/D-pad focus navigation, accessible names, 88 px Captain Naps dismiss target.

### Changed
- Android build target Godot 4.5.1 (Play: 16 KB pages, target API 36). The project still runs
  on 4.3 for development.
- vitest 4 (dev-only advisories).

## [0.3.0] — 2026-10-15 — the Interdimensional Delivery Crew

See [docs/CHARACTER_SYSTEM.md](docs/CHARACTER_SYSTEM.md) for the audit, architecture and risks.

### Added
- Character system: packages are the Interdimensional Delivery Crew — Bloop (orange ●), Zip
  (blue ■), Glitch (purple ▲), Mochi (green ◆) — plus the mascot Captain Naps and engineer
  Dr. Rix. Original procedural vector art in a consistent direction (v1, not a final
  illustration pass), full and compact detail levels chosen by pixel size.
- Animation state machine (idle, selected, moving, waiting, surprised, failed, delivered,
  celebrating) as pure functions of simulation frames: interruptible, deterministic, frozen by
  Reduce motion. Characters wait in source "pods", react when tapped, celebrate together on
  their docks; per-world celebration themes.
- Captain Naps on Home (optional bubble, tap for a line), on the win card (reacts to real
  moments: first win, perfect, all-together arrival, near miss, efficient big solve) and
  presenting the daily. Dr. Rix introduces crossings, junctions and three colours; Captain Naps
  introduces new worlds — all in the existing banner, never a modal.
- Data-driven dialogue engine (`data/crew/dialogue.en.json`): events, priority, cooldown
  (incl. show-once), probability, conditions, templates; per-id translation fallback.
- The Crew collection: roster, detail page with animation preview, 15 looks + a starry-eyed
  celebration unlocked through play (validated against current content), equip persistence,
  unseen markers and a single unlock toast. Existing saves receive looks already earned.
- Share card crew lineup with a featured character (the run's final delivery) and one reaction.
- Feature flags `characters_enabled`, `character_animations_enabled`,
  `mascot_dialogue_enabled`, `character_collection_enabled`, `sci_fi_theme_enabled`;
  `presentation` experiment (`hybrid` control, `minimal`, `full` with a sci-fi backdrop).
- Settings: Character packages, Character animations, Captain Naps chatter.
- Analytics: `character_exposed`, `character_animation_played`, `character_collection_opened`,
  `cosmetic_unlocked`, `cosmetic_equipped`, `character_dialogue_shown`,
  `character_dialogue_dismissed`; documented per-arm queries.
- Tests: 18 crew unit tests, a 121-check crew scene suite (incl. pixel tests that no look covers
  a symbol), character sheet renderer, crew benchmark.

### Changed
- Failure banner names the character and shows its confused face; a repeat of the same failure
  may add a character quip after the tip.
- Home bottom row: Worlds · The Crew · Friends (when the collection is enabled).
- Characters are pooled canvas items re-recorded only when their face changes; running cost
  equals the classic boxes.

### Fixed
- Tapping a source showed the "Pinned belt" coach message (sources were never belts).
- Reset after a failed run with no moves didn't clear the failure marks.

## [0.2.0] — 2026-10-15 — gameplay, retention and sharing upgrade

See [docs/UPGRADE_AUDIT.md](docs/UPGRADE_AUDIT.md) for the audit that drove these changes.

### Added
- Game feel: tactile tiles with depth (raised vs pinned), press pre-tilt and 140 ms eased snap,
  constant-speed package motion with start/stop easing, path illumination, rolling belts, dock
  fill/pop, skippable 1.2 s success celebration, progressive star reveal.
- Audio: mechanical rotate clicks, perfect-solve and star sounds, ambient music loop (own setting),
  haptic patterns.
- Onboarding coach for levels 1–5; progressive three-step hints (area → tile → rotation).
- Five themed worlds (Little Workshop, Candy Factory, Parcel Station, Neon Circuit, Space
  Logistics); two transition levels (`x26` Right of Way, `x31` Third Shift) — 36 levels.
- Difficulty model with CI-enforced spike / new-mechanics checks and a generated report.
- Friend challenges (server-verified, no sign-up), landing page `/c/:code`, results table.
- Shareable 1080×1350 result card; replays of best solutions with a clean recording view.
- Daily attempts tracking; feature flags and A/B experiments with deterministic bucketing.
- Analytics: first launch, tutorial, session end, background/resume, unclean-session proxy,
  share/challenge funnel, experiment properties; documented retention and funnel queries.
- Tests: 1,000-puzzle generator property test, UI layout tests on five aspect ratios, rapid-tap
  convergence, challenge API and E2E coverage, board rendering benchmark.

### Changed
- Failure feedback names the package and cause in a banner above the board (no longer a toast
  over it) and marks the failing tile and path; toasts moved to the top edge.
- Shape symbols always drawn on packages and docks; setting renamed "Larger shape symbols".
- Board renderer split into per-tile canvas items: ~4× less CPU per frame on the largest board.
- Palette tuned (accent `#FFAE76`, success `#53C5A2`, error `#E97979`, text `#282B3C`).

### Fixed
- Level 26's tip taught packages waiting on a level where no package waits (moved to `x26`).
- Off-board failures highlighted no cell.
- E2E script left the API's child process running.

### Database
- Migration `20261015100000_friend_challenges` (additive: `friend_challenges`,
  `friend_challenge_attempts`).

## [0.1.0] — 2026-10-15

### Added
- Deterministic rules engine (TypeScript) with simulation, exact minimum-rotation solver, hints,
  `gen-1` procedural generator and replay verification; GDScript port with byte-identical parity.
- 34 curated levels (9 hand-designed teaching levels, 25 reviewed generator levels).
- Godot client: home, levels, gameplay, daily, profile and settings screens; tutorial; endless mode;
  offline daily practice; atomic autosave and resume; synthesised SFX; haptics; colour symbols;
  reduced motion; opt-in analytics.
- REST API: guest auth with refresh-token rotation, account linking, idempotent progress sync,
  levels, daily challenges with server-verified submissions, daily/weekly/global leaderboards,
  achievements, remote config, data export/erasure, purchase entitlement verification framework.
- PostgreSQL schema and migrations; Docker image; docker-compose; Render blueprint; GitHub Actions
  CI (typecheck, lint, unit, integration, Godot, E2E, audit, secret scan, Docker, Android export).
- Load test harness and measured results; release, security, analytics and policy documentation.
