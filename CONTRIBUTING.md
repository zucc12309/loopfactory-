# Contributing

## Setup
```bash
npm ci
docker compose up -d db          # or a local PostgreSQL 16
cp .env.example .env
```
Install Godot 4.3 for client work.

## Before opening a pull request
```bash
npm run typecheck && npm run lint
npm test -w @loopfactory/engine
npm test -w @loopfactory/api
./scripts/test-game.sh
npm run levels:check && npm run fixtures:check && npm run openapi -w @loopfactory/api -- --check
```
CI runs all of these plus the end-to-end test, migration drift check, dependency audit, secret
scan, Docker build and Android export.

## Ground rules
1. **Rules change in both engines.** Edit `packages/engine` first, mirror it in
   `apps/game/scripts/engine`, then `npm run fixtures:build`. Bump `GENERATOR_VERSION` if
   generation output changes (old endless/daily levels stay verifiable under their version).
2. **Levels:** edit `scripts/levels/curated-source.ts`, run `npm run levels:build -- --review`, look
   at the ASCII renders, and bump `CONTENT_VERSION` when existing boards change.
3. **API:** declare endpoints in `services/api/src/routes/index.ts` with schemas from
   `packages/contracts`; regenerate the OpenAPI document; add an integration test.
4. **Database:** never edit applied migrations; add a new one. Prefer expand → migrate → contract.
5. **No secrets** in the repo or the client config. Keystores are git-ignored.
6. **Player-friendly design:** no energy systems, forced waits or pay-to-win.

Commit messages: imperative mood, explain *why* in the body when it isn't obvious.
