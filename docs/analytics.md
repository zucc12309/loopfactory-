# Analytics: event taxonomy, metrics and queries

## Principles

* **Opt-in.** Consent is asked once, **after the player's first delivery** (at the transition to
  the next puzzle, or on Home once progress exists — never on a fresh Home, over the first puzzle
  or over a celebration). It can be changed in Settings. Nothing is queued, stored or sent without
  it, and nothing that happened before consent is ever backfilled.
* **Random identity.** The analytics id is random: not a device id, not the account id. It resets
  when data is deleted.
* **No personal data.** No names, emails, locations or advertising ids.
* **Batched sends.** Events are sent every 30 s and on backgrounding. While consent is on, the queue
  is also kept on disk (`user://analytics-queue.json`, at most one write per frame) so offline
  events survive a restart; withdrawing consent deletes it and abandons any batch in flight.
* **Deduplication.** Every event has a random `uuid`; a batch retried after a lost response
  carries the same ids so the provider can drop duplicates. One-time events (`first_*`,
  `consent_granted`, `tutorial_start`) are recorded at most once per install.

Provider adapter: `apps/game/scripts/core/analytics.gd`, set in `config/client.json`. Options are
`none` (default), `debug` (prints events) and `posthog` (HTTP batch API, EU host by default).
**No analytics project is configured**, so none of the queries below have been run against real
data.

## Common properties (every event)

`schema` (2), `session_id` (random; continues across a relaunch within 30 min, new after 30 min
away), `app_version`, `build`, `environment`, `platform`, `os_major`, `device_class`
(phone/tablet/desktop — never a model or device id), `uuid`, `timestamp` (UTC), `distinct_id` (the
random analytics id), and `exp_<key>` for every running experiment ([experiments.md](experiments.md)).

**Schema 2 changes (2026-10-15):** `share_clicked` and `share_completed` are retired —
`share_completed` counted a clipboard copy or an unconfirmed plugin call as a completed share. They
are replaced by the precise events below. New: `consent_granted`, `first_rotation`, `first_run`,
`first_delivery`, `challenge_loaded`, `challenge_started`, `network_error`, `app_error`,
`guest_identity_created`.

## Events

Naming is `object_action` in snake_case. Every name is declared in `Analytics.EVENTS`, and a unit
test scans the code to check that each `Analytics.track` call uses a declared name.

| Event | When | Properties |
|---|---|---|
| `app_open` | autoload ready | `cold_start` |
| `first_launch` | first ever session on this install | — |
| `session_start` | launch (unless continuing a session < 30 min old), return after more than 30 min away, or consent granted | `trigger` (`launch` / `return` / `consent`) |
| `consent_granted` | player opts in (once per install) — **the cohort anchor** | `levels_completed`, `sessions`, `surface` |
| `guest_identity_created` | a server guest account was created (first time, or after the old one was revoked) | `replaced` |
| `session_end` | close, or a background timeout | `session_seconds`, `reason` (`close` / `background_timeout`) |
| `app_background` | app paused / focus lost (calls, home button) | `session_seconds`, `screen` |
| `app_resume` | back within 30 min, or relaunched within 30 min of the last activity | `away_seconds` / `cold_start` |
| `previous_session_unclean` | the previous session ended while in the foreground (crash or kill) | `previous_session_id` |
| `tutorial_start` | level 1 opened for the first time | `flow` |
| `tutorial_complete` | first clear of level 5 | `flow` |
| `first_rotation` / `first_run` / `first_delivery` | first belt turn / first Run / first successful delivery on this install (only if consent was on at that moment) | `level_id`, `kind` (`attempts` on delivery) |
| `level_start` | play screen opened | `level_id`, `level_number`, `kind`, `difficulty`, `par` |
| `level_complete` | successful run | `level_id`, `level_number`, `kind`, `moves`, `par`, `stars`, `hints`, `attempts` |
| `level_fail` | failed run | `level_id`, `kind`, `reason` |
| `level_retry` | Run pressed after a failure | `level_id`, `kind`, `attempt` |
| `hint_used` | any hint step | `level_id`, `kind`, `step` (1–3) |
| `replay_viewed` | replay screen opened | `level_id`, `moves` |
| `daily_challenge_entry` | daily opened from Home | `surface` (`card` / `banner`) |
| `daily_challenge_started` | official daily started | `date` |
| `daily_challenge_completed` | official daily solved | `moves`, `attempts` |
| `share_card_created` | result card rendered and shown | `kind` |
| `share_text_copied` | Copy text / Copy invite pressed, or the fallback after a failed native share | `kind`, `fallback` |
| `share_image_saved` | image written to a folder the player can open (desktop Pictures) | `kind` |
| `share_sheet_opened` | the native chooser OPENED (plugin builds only). Which app was picked, or whether anything was sent, is not observable | `kind`, `with_image` |
| `share_sheet_closed` | iOS only: the share sheet closed. `result` is `completed` (the chosen activity said it finished — **not** proof anyone received it), `cancelled` or `failed` | `kind`, `result` |
| `challenge_create_clicked` | "Challenge" tapped | `kind`, `level_id` |
| `challenge_created` | server issued a code | `kind`, `level_id` |
| `challenge_link_opened` | a code looked up / an App Link or launch argument received | `source` (`code_entry` / `app_link` / `launch_argument`) |
| `challenge_loaded` | the challenge puzzle was fetched and validated | `attempts` |
| `challenge_started` | the recipient started playing it | `source` |
| `challenge_completed` | recipient solved, verified comparison | `outcome` (`win` / `tie` / `lose`) |
| `character_exposed` | characters shown on a surface (once per session per surface) | `surface` (`board` / `home` / `daily`), `variant`, `detail`, `level_id` / `character` |
| `character_animation_played` | notable crew animations only: first source poke per level, success celebration, Home tap, Crew preview | `character`, `animation`, `surface`, `moment` |
| `character_collection_opened` | The Crew opened | `unseen` |
| `cosmetic_unlocked` | a look unlocked through play | `cosmetic_id`, `character` |
| `cosmetic_equipped` | a look worn (or removed: empty id) | `cosmetic_id`, `character` |
| `character_dialogue_shown` | a crew line displayed | `character`, `event`, `line_id` |
| `character_dialogue_dismissed` | Home bubble closed with × | `character`, `line_id`, `surface` |
| `purchase_started` / `purchase_completed` | reserved; no store is integrated | `product_id` |
| `network_error` | sync failed (recoverable; once per session) | `category`, `fatal`, scrubbed `detail` |
| `app_error` | save failure/recovery, unclean previous exit (fatal), config problem, share failure, diagnostic test | `category`, `fatal`, scrubbed `detail` |

## Consented cohorts

Only players who opt in are observable, and consent is asked after the first delivery, so:

* **Install counts and the pre-consent funnel are NOT measured.** Store installs come from Play
  Console; drop-off before the first delivery is unobservable for players who never consent.
  `first_rotation` / `first_run` / `first_delivery` appear only for the minority who turned
  analytics on in Settings before playing.
* **Cohort anchor:** `consent_granted` (once per install). `levels_completed` on it says where in
  the game the player consented.
* **Funnel (per consented cohort, by consent day):** `consent_granted` → `level_complete` with
  `level_number` ≥ 5 (tutorial done) → ≥ 12 (end of world 1) → `session_start` on day 1 / 7 after
  consent → `daily_challenge_completed` → `challenge_completed`.
* **Retention** is measured from the consent day, not the install day, and must be reported as
  "D1 after consent among consenting players". Never extrapolate it to all installs.
* Consent rate itself = `consent_granted` / Play Console first-opens is the only cross-source
  ratio (approximate: different identities).

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

## Character system

The brief's `level_completed`, `level_retried`, `daily_challenge_completed` and `result_shared`
are the existing `level_complete`, `level_retry`, `daily_challenge_completed` and
`share_completed`. Compare the `presentation` experiment's arms (`exp_presentation`:
`hybrid` vs `minimal`, plus `full`) — never before/after release, which mixes in seasonality and
acquisition changes. Puzzles, difficulty and progression are identical across arms.

| Metric | Definition (per arm) |
|---|---|
| Tutorial completion | `tutorial_complete` / `tutorial_start` |
| First-session completion | share of new players clearing `c01` in their first session (query above, grouped by `exp_presentation`) |
| Time to first successful action | median seconds from `first_launch` to that player's first `level_complete` |
| D1 / D7 retention | retention query above, grouped by the arm of the `first_launch` event |
| Levels per session | `count(level_complete)` / `count(distinct session_id)` |
| Voluntary share rate | players with `share_completed` / players with a daily completion |
| Crash-free sessions | proxy above, per arm |
| Crew engagement (diagnostic, not a goal) | `character_collection_opened`, `cosmetic_equipped`, dialogue dismiss rate = `character_dialogue_dismissed` / `character_dialogue_shown` |

```sql
-- Time to first successful action, by presentation arm
SELECT f.arm, quantile(0.5)(dateDiff('second', f.t0, c.t1)) AS median_seconds, count() AS players
FROM (SELECT distinct_id, min(timestamp) AS t0, any(properties.exp_presentation) AS arm
      FROM events WHERE event = 'first_launch' GROUP BY distinct_id) f
JOIN (SELECT distinct_id, min(timestamp) AS t1 FROM events WHERE event = 'level_complete' GROUP BY distinct_id) c
  USING distinct_id
GROUP BY f.arm
```

```sql
-- Levels per session and share rate, by arm
SELECT properties.exp_presentation AS arm,
  countIf(event = 'level_complete') / uniqIf(properties.session_id, event = 'session_start') AS levels_per_session,
  uniqIf(distinct_id, event = 'share_completed') / uniqIf(distinct_id, event = 'daily_challenge_completed') AS share_rate
FROM events GROUP BY arm
```

`exp_presentation` is only attached while the experiment is running; players who arrived before it
started have no arm and must be excluded. **No result exists yet** — no analytics project is
connected, so nothing here says the crew improves retention.

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
