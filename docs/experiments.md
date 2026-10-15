# Feature flags and experiments

Client code: `apps/game/scripts/core/flags.gd` (`LFFlags`). Configuration is the remote config
served by `GET /api/v1/config` and stored in `remote_config_versions`.

## Rules

* **Control by default.** Every experiment's first variant is the shipped experience. A
  player gets a non-control variant only when the remote config enables that experiment. With
  no server, offline, or on first launch, everyone gets control.
* **Stable, private bucketing.** The bucket is `FNV-1a(analyticsId + ":" + key) % 100`. The
  analytics id is random and resets on data deletion, and no device id is used. A player keeps
  the same variant across sessions, and experiments are independent of each other.
* **Analysable.** Every analytics event carries `exp_<key>` for each running experiment.
* **No dark patterns.** Experiments may change pacing and placement, never outcomes, odds,
  prices or scoring. Results are reported against player-centric guardrails (completion,
  retention, crash-free sessions), not time-in-app alone.

## Experiments

| Key | Variants (control first) | What it changes |
|---|---|---|
| `tutorial_flow` | `coach`, `tips_only` | Interactive coach on levels 1–5 vs. text tips |
| `celebration_ms` | `1200`, `800` | Success celebration length (always skippable) |
| `challenge_button` | `secondary_row`, `beside_next` | Placement of "Challenge a friend" on the result card |
| `daily_entry` | `card`, `banner` | Daily challenge as a Home card vs. a banner above Continue |
| `difficulty_ramp` | `standard`, `gentle` | Endless tier thresholds ×1.0 vs ×1.5 |
| `presentation` | `hybrid`, `minimal`, `full` | Character presentation: expressive packages + Captain Naps (shipped), the pre-crew look, or hybrid + sci-fi backdrop ([CHARACTER_SYSTEM.md](CHARACTER_SYSTEM.md#7-presentation-variants-and-feature-flags)) |

## Feature flags (kill switches)

`remoteConfig.flags.<name>` — booleans, default `true` when absent (`LFFlags.FLAGS`). Turning one
off removes that feature for everyone on their next config fetch, without a client update.

| Flag | Turns off |
|---|---|
| `characters_enabled` | all character features (classic packages, logo on Home, no Crew, no lines) |
| `character_animations_enabled` | character motion (expressions stay) |
| `mascot_dialogue_enabled` | every crew line (banners, Home bubble, win card, daily) |
| `character_collection_enabled` | The Crew screen and unlock toasts (unlocks are still recorded) |
| `sci_fi_theme_enabled` | the backdrop of the `full` presentation variant |

## Remote config

```json
{
  "experiments": {
    "celebration_ms": { "enabled": true, "weights": [50, 50] },
    "daily_entry": { "force": "banner" },
    "presentation": { "enabled": true, "weights": [34, 33, 33] }
  },
  "flags": { "mascot_dialogue_enabled": true }
}
```

* `enabled: true` with `weights` (one per variant) runs a split. Missing or mismatched weights
  mean an equal split.
* `force` rolls one variant out to everyone. Use the control variant to roll back. An unknown
  forced value falls back to control.
* To publish, insert a new `remote_config_versions` row with `active = true`. Clients fetch it at
  startup.

Unit tests cover: control by default, disabled experiments, a stable roughly 50/50 split over
2,000 ids, forced rollouts and unknown values (`tests/test_upgrade.gd`).

## Suggested first experiments (hypotheses)

| Experiment | Primary metric | Guardrails |
|---|---|---|
| `tutorial_flow` | tutorial completion (`tutorial_complete` / `tutorial_start`) | D1 retention, level 6 start rate |
| `celebration_ms` | levels per session | D1, perceived delight (survey) |
| `challenge_button` | `challenge_created` / `level_complete` | Next-level rate |
| `daily_entry` | `daily_challenge_entry` / sessions | campaign progress |
| `difficulty_ramp` | endless puzzles per session | endless abandonment |
| `presentation` | D1 / D7 retention, levels per session (`hybrid` vs `minimal`) | tutorial completion, time to first success, crash-free sessions, share rate |
