# Changelog

All notable changes to this project are documented here (format: Keep a Changelog, versions: SemVer).

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
