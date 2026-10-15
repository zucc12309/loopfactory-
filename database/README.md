# Database

PostgreSQL 16 managed with Prisma. `schema.prisma` is the source of truth; `migrations/` holds the
versioned SQL that production applies with `prisma migrate deploy`.

```bash
# create a migration after editing schema.prisma
npm run db:migrate:dev -w @loopfactory/api -- --name <change>
# apply (CI / production)
npx prisma migrate deploy --schema database/schema.prisma
```

Tables: `players`, `player_auth_identities`, `refresh_tokens`, `levels`, `level_packs`,
`player_level_progress`, `active_puzzle_states`, `daily_challenges`, `challenge_submissions`,
`leaderboard_entries`, `achievements`, `player_achievements`, `sync_operations`,
`remote_config_versions`, `purchase_entitlements`, `privacy_requests`.

Conventions: server timestamps are authoritative (`timestamptz`); client clocks are stored in
separate `client_*` columns and only drive last-writer-wins for device-owned data; every
player-owned row cascades on account deletion. Retention rules: `docs/deployment.md`.
