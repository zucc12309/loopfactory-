# Character animations

Code: `scripts/crew/crew_anim.gd` (state machine), `scripts/crew/crew_painter.gd` (drawing),
`scripts/ui/board_view.gd` (`_update_crew`, source pods), `scripts/ui/crew_portrait.gd`.

## Model

A pose is a **pure function**:

```
LFCrewAnim.pose(body, state, age_in_state, global_time, seed, ctx) -> {dx, dy, sx, sy, rot,
    eyes, look, mouth, brows, arms, foot, ghost, sweat, z}
```

* No tweens, timers or random numbers. "Random" glances use a hash of (seed, time step), so a
  replay or screenshot looks identical every time.
* The board derives `state` and `age` from the current simulation frame (spawned, moved,
  waiting, delivered, crashed) and the frame's progress. It never writes anything back.
* Because nothing is stored per animation, every state is **interruptible**: undo, reset,
  replay, Stop, rapid Run/Stop, backgrounding and restoring a saved session simply change the
  inputs, and the next frame shows the right pose. There is nothing to cancel or leak.

## States

| State | Trigger on the board | Duration | Bloop | Zip | Glitch | Mochi |
|---|---|---|---|---|---|---|
| IDLE | waiting in its source before Run | loops; blink 140 ms every 2.2–3.4 s | glances around, smirk, confident brows | darting nervous looks | odd circling eye movements | slow sleepy blinks, occasional "z" |
| SELECTED | package spawns on Run; player taps a source | bounce 160 ms (reaction held 350 ms) | energetic hop, arms up | startled jump back, sweat | harmless RGB "glitch" ghost | wakes up wide-eyed |
| MOVING | travelling along belts | per step | leans forward into the turn | trembles | playful wobble | squash-and-stretch |
| WAITING | blocked by another package / queued in a source | loops | taps a foot | nervous fast blinking | silly faces | yawns |
| SURPRISED | blocked route (crash in progress) | 250 ms hop | eyes wide, "o" mouth, arms up | + sweat | | |
| FAILED | wrong dock; after a failed run (shown in its source) | 300 ms reaction, then holds | shocked, then pretends nothing happened (side-eye, whistle) | comic panic | confused tilt | confused and sleepy |
| DELIVERED | arriving at its dock | 380 ms | victory jump | relieved smile | spins | happy bounce |
| CELEBRATING | success, every dock together | 450 ms bounce loop for the celebration (1.2 s, skippable) | | | spins after a perfect solve | |

World themes change only the celebration: Candy Factory bounces 1.4× higher, Neon Circuit adds
a cyan rim light, Space Logistics a helmet visor arc. The "Starry-eyed celebration" look swaps
happy eyes for stars.

These durations are starting values within the brief's ranges (blink 100–180 ms, selection
120–180 ms, delivery 250–450 ms, failure 200–350 ms, group 600–1000 ms per loop) and should be
tuned on devices.

## Timing never changes the game

* Package **positions** come from the same interpolation as before (constant speed, eased only
  at start/stop). Characters add hops/leans as a transform on top, capped at 0.45 of the body
  size (portraits keep the contact shadow on the ground; on the board it travels with the
  character so the whole character is one cached drawing).
* Playback length is `frames × step_time` in both presentations; the celebration length still
  comes from the `celebration_ms` experiment. Tested: same result, same deliveries and the same
  playback length (±0.06 s) with characters on and off.

## Reduced motion and settings

* **Reduce motion** (accessibility) or **Character animations off** (Settings, or the remote
  `character_animations_enabled` flag): every pose is frozen — no hop, lean, squash, wobble,
  blink, glitch or foot tap — but expressions still change (they carry meaning: a confused face
  on the failing package). Tested for every state and character.
* **Character packages off**: the classic package boxes return.

## Rendering and performance

* Travelling and celebrating characters are **pooled canvas items** (`CrewNode`). Each frame
  sets position, rotation, scale (hop, lean, squash, spawn pop, delivery shrink) and modulate
  (fade). Draw commands are re-recorded only when the **face** changes (signature of eyes, mouth,
  brows, arms, look, effects). Pool nodes are reused across runs; Stop hides them.
* Source pods draw inside the tile node and use the tile's appearance signature, so an idle
  character re-records only on a blink or glance.
* Bodies use cached native `StyleBoxFlat`s and native circles; anti-aliasing stays 1 px because
  the painter transforms points itself instead of scaling the canvas.
* Measured (desktop, software rendering, [performance.md](performance.md)): running the largest
  board costs p50 ≈ 1.1 ms with characters vs ≈ 1.3 ms with classic boxes; idle editing costs
  ≈ 0.25 ms more than classic.

## Sound and haptics

* Poking a character: a tiny rising "boop" (pitch per colour) + light haptic.
* Tapping Captain Naps on Home: a soft "mrrp".
* Existing delivery, success and failure sounds/haptics are unchanged. All respect the Sound
  effects and Vibration settings.
