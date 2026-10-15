# API overview

Base path `/api/v1`. Machine-readable spec: `docs/api/openapi.json` (OpenAPI 3.1, generated from
the route registry; also served at `GET /openapi.json`). Errors always use
`{"error": {"code", "message", "requestId", "details?"}}`.

## Authentication flow
1. `POST /auth/guest` → `{player, accessToken (15 min JWT), accessTokenExpiresIn, refreshToken}`.
2. Send `Authorization: Bearer <accessToken>`.
3. On 401/expiry: `POST /auth/refresh {refreshToken}` → new pair. The old refresh token is now
   invalid; presenting it again revokes the whole session family.
4. Optional: `POST /auth/link {provider: google|apple, idToken, onConflict}`. If the identity
   belongs to another account, `onConflict: "switch"` returns that account's tokens (restore).

## Endpoint groups
| Group | Endpoints |
|---|---|
| Auth | `POST /auth/guest`, `/auth/refresh`, `/auth/link`, `/auth/logout` |
| Player | `GET/PATCH/DELETE /player/me` |
| Progress | `GET /progress`, `POST /progress/sync`, `GET /progress/history` |
| Levels | `GET /levels`, `GET /levels/packs`, `GET /levels/:id` |
| Daily | `GET /challenges/daily?date=`, `POST /challenges/daily/submit`, `GET /challenges/daily/leaderboard` |
| Friend challenges | `POST /challenges/friend`, `GET /challenges/friend/:code`, `POST /challenges/friend/:code/attempts`, `GET /challenges/friend/:code/results` ([sharing.md](sharing.md)) |
| Leaderboards | `GET /leaderboards/global`, `/weekly?week=YYYY-Www`, `/daily?date=` |
| Achievements | `GET /achievements`, `GET /achievements/me` |
| Config | `GET /config` (ETag); includes `experiments` ([experiments.md](experiments.md)) |
| Privacy | `GET /privacy/export`, `POST /privacy/delete-request {confirm:true}` |
| Purchases | `POST /purchases/verify`, `GET /purchases/entitlements` |
| Ops | `GET /health`, `GET /ready` |
| Web | `GET /c/:code` — challenge landing page (HTML, no scripts) |

## Sync operation types
`level_complete` (with `moves` replay, or `null` for legacy/unverifiable), `settings`,
`active_puzzle`. Each needs a unique `opId`; see `docs/sync.md` for merge rules.

## Versioning
Additive changes stay in v1 (new optional fields, new endpoints). Breaking changes ship as `/api/v2`
while v1 is kept until `minSupportedClientVersion` (remote config) passes the old clients.
