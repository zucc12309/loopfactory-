# Analytics: event taxonomy, metrics and queries

## Principles

* **Opt-in.** Consent is asked once and can be changed in Settings. Nothing is queued or sent
  without it.
* **Random identity.** The analytics id is random: not a device id, not the account id. It resets
  when data is deleted.
* **No personal data.** No names, emails, locations or advertising ids.
* **Batched sends.** Events are sent every 30 s and on backgrounding.

Provider adapter: `apps/game/scripts/core/analytics.gd`, set in `config/client.json`. Options are
`none` (default), `debug` (prints events) and `posthog` (HTTP batch API, EU host by default).
**No analytics project is configured**, so none of the queries below have been run against real
data.

## Common properties (every event)

`session_id` (random; a new one after 30 min in the background), `app_version`, `platform`,
`timestamp` (UTC), `distinct_id` (the random analytics id), and `exp_<key>` for every running
experiment ([experiments.md](experiments.md)).

## Events

Naming is `object_action` in snake_case. Every name is declared in `Analytics.EVENTS`, and a unit
test scans the code to check that each `Analytics.track` call uses a declared name.

| Event | When | Properties |
|---|---|---|
| `app_open` | autoload ready | — |
| `first_launch` | first ever session on this install | — |
| `session_start` | launch, or return after more than 30 min in the background | `resumed` |
| `session_end` | close, or a background timeout | `session_seconds`, `reason` (`close` / `background_timeout`) |
| `app_background` | app paused / focus lost (calls, home button) | `session_seconds`, `screen` |
| `app_resume` | back within 30 min | `away_seconds` |
| `previous_session_unclean` | the previous session ended while in the foreground (crash or kill) | `previous_session_id` |
| `tutorial_start` | level 1 opened for the first time | `flow` |
| `tutorial_complete` | first clear of level 5 | `flow` |
| `level_start` | play screen opened | `level_id`, `level_number`, `kind`, `difficulty`, `par` |
| `level_complete` | successful run | `level_id`, `level_number`, `kind`, `moves`, `par`, `stars`, `hints`, `attempts` |
| `level_fail` | failed run | `level_id`, `kind`, `reason` |
| `level_retry` | Run pressed after a failure | `level_id`, `kind`, `attempt` |
| `hint_used` | any hint step | `level_id`, `kind`, `step` (1–3) |
| `replay_viewed` | replay screen opened | `level_id`, `moves` |
| `daily_challenge_entry` | daily opened from Home | `surface` (`card` / `banner`) |
| `daily_challenge_started` | official daily started | `date` |
| `daily_challenge_completed` | official daily solved | `moves`, `attempts` |
| `share_clicked` | share sheet opened | `kind`, `surface` |
| `share_completed` | text copied, image saved or native share | `kind`, `method` |
| `challenge_create_clicked` | "Challenge" tapped | `kind`, `level_id` |
| `challenge_created` | server issued a code | `kind`, `level_id` |
| `challenge_link_opened` | a code looked up | `source` |
| `challenge_completed` | recipient solved, verified comparison | `outcome` (`win` / `tie` / `lose`) |
| `purchase_started` / `purchase_completed` | reserved; no store is integrated | `product_id` |

## Dashboards and queries

The queries below use PostHog HogQL (table `events`, columns `event`, `distinct_id`,
`timestamp`, `properties`).

**D1 / D7 / D30 retention.** Share of players with any event on day N after `first_launch`.

```sql
WITH cohort AS (
  SELECT distinct_id, toDate(min(timestamp)) AS d0 FROM events
  WHERE event = 'first_launch' GROUP BY distinct_id)
SELECT d0,
  count() AS players,
  countIf(has(days, d0 + 1))  / count() AS d1,
  countIf(has(days, d0 + 7))  / count() AS d7,
  countIf(has(days, d0 + 30)) / count() AS d30
FROM cohort JOIN (
  SELECT distinct_id, groupUniqArray(toDate(timestamp)) AS days FROM events
  WHERE event = 'session_start' GROUP BY distinct_id) USING distinct_id
GROUP BY d0 ORDER BY d0
```

**First-session completion.** Share of new players who clear level 1 in their first session.

```sql
SELECT countIf(cleared) / count() FROM (
  SELECT e.distinct_id,
    max(e.event = 'level_complete' AND e.properties.level_id = 'c01') AS cleared
  FROM events e
  JOIN (SELECT distinct_id, argMin(properties.session_id, timestamp) AS s FROM events WHERE event = 'first_launch' GROUP BY distinct_id) f
    ON e.distinct_id = f.distinct_id AND e.properties.session_id = f.s
  GROUP BY e.distinct_id)
```

**Level-by-level abandonment.** Starts with no completion by the same player.

```sql
SELECT properties.level_number AS n, properties.level_id AS id,
  uniqIf(distinct_id, event = 'level_start') AS started,
  uniqIf(distinct_id, event = 'level_complete') AS completed,
  1 - completed / started AS abandonment
FROM events WHERE properties.kind = 'campaign' AND event IN ('level_start', 'level_complete')
GROUP BY n, id ORDER BY toInt(n)
```

**Average rotations, attempts and hints per level.** Use these to re-fit
[difficulty.md](difficulty.md).

```sql
SELECT properties.level_id, avg(toFloat(properties.moves)) AS rotations, avg(toFloat(properties.par)) AS par,
  avg(toFloat(properties.attempts)) AS attempts, avg(toFloat(properties.hints)) AS hints
FROM events WHERE event = 'level_complete' AND properties.kind = 'campaign'
GROUP BY properties.level_id
```

**Share conversion.**
`uniq(share_completed) / uniq(level_complete where kind in (daily, offline_daily))`.

**Challenge funnel.**
`challenge_create_clicked → challenge_created → challenge_link_opened → challenge_completed`.
Acceptance rate is `challenge_completed / challenge_created`. Viral coefficient is approximated
by `first_launch` events within 48 h of a `challenge_link_opened` with `source = code_entry`.

**Crash-free sessions (proxy).** `1 − count(previous_session_unclean) / count(session_start)`.
A session counts as clean when it reaches background or close. Process death while in the
background (normal on Android) is therefore not counted as a crash. Native crash reporting (Play
Console vitals, or sentry-godot) is still needed for stack traces.

## Initial targets (hypotheses, not benchmarks)

| Metric | Target |
|---|---|
| Tutorial completion | ≥ 85 % |
| First five levels completed | ≥ 65 % |
| D1 retention | ≥ 35 % |
| D7 retention | 10–15 %+ |
| Organic share rate | ≥ 5 % of daily completions |
| Crash-free sessions | ≥ 99 % |

Optimise for repeat enjoyment (completion, D1/D7, shares), not raw time in app. Server-side
truth for completions, dailies, challenges and leaderboards lives in PostgreSQL and does not
depend on consent. High-volume events are intentionally not stored there.
