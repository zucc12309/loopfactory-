# Changelog

All notable changes to this project are documented here (format: Keep a Changelog, versions: SemVer).

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
