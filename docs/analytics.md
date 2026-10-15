# Analytics: event taxonomy & metrics

Principles: opt-in consent (asked once, changeable in Settings), random analytics id (not device
id, not account id), no names/emails/locations/ad ids, batched sends, nothing sent without consent.
Provider adapter: `apps/game/scripts/core/analytics.gd` — `none` (default), `debug`, `posthog`
(EU host by default). Configure in `config/client.json`.

## Common properties (every event)
`session_id` (random per launch), `app_version`, `platform`, `timestamp` (UTC ISO), `distinct_id`
(random analytics id).

## Events

| Event | When | Properties |
|---|---|---|
| `app_open` | autoload ready | — |
| `session_start` | each launch | — |
| `level_start` | play screen opened | `level_id`, `kind` (campaign/endless/daily/offline_daily), `difficulty`, `par` |
| `level_complete` | successful run | `level_id`, `kind`, `moves`, `par`, `stars`, `hints` |
| `level_fail` | failed run | `level_id`, `kind`, `reason` (off_board, disconnected, wrong_destination, deadlock, loop) |
| `level_retry` | Run pressed after a failure | `level_id`, `kind` |
| `hint_used` | hint shown | `level_id`, `kind` |
| `daily_challenge_started` | official daily opened | `date` |
| `daily_challenge_completed` | official daily solved | `moves` |
| `share_clicked` | result copied | `kind` |
| `purchase_started` | store flow opened (when stores are configured) | `product_id` |
| `purchase_completed` | server verified purchase | `product_id` |

## Metric definitions

| Metric | Definition |
|---|---|
| D1 / D7 / D30 retention | share of users with `session_start` on day N after first `app_open` (UTC days) |
| Avg session duration | time between first and last event per `session_id` (PostHog session) |
| Levels per session | `level_complete` count / sessions |
| Level completion rate | `level_complete` / `level_start` per `level_id` |
| Retry rate | `level_retry` / `level_start` per `level_id` |
| Hint usage | `hint_used` / `level_start`; per level to find spikes |
| Difficulty abandonment | `level_start` without `level_complete` in the same session, by `level_id` / `difficulty` |
| Crash-free sessions | from the crash reporter (Sentry / Play Console vitals): sessions without a crash / all sessions |

Server-side truth (unaffected by consent) for completions, dailies and leaderboards lives in
PostgreSQL; high-volume events are intentionally not stored there.
