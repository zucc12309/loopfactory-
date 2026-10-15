# Game feel

How every interaction is made to feel good, and the numbers behind it. All timings live as
constants in `apps/game/scripts/ui/board_view.gd` (board) or `scripts/ui/screens/play.gd`
(screen). They are starting values for playtesting, not final.

## Principles

1. **Logic first, animation second.** A tap changes the model on release, the same frame. The
   view only catches up. Animations never gate input, so rapid taps are never lost. A UI test
   makes 40 taps and undos with no frames in between, then checks that the view lands exactly on
   the model's rotations within 0.4 s.
2. **Deterministic playback.** The simulation runs to completion before playback starts. The
   renderer interpolates between recorded frames, so frame rate and effects can never change an
   outcome.
3. **Feedback never covers the board.** Tips, coaching, hints and failure explanations use the
   banner above the board. Toasts appear at the top edge. Modals are reserved for results.
4. **Respect accessibility.** Reduce motion turns off rotation easing, pre-tilt, pops, shakes,
   confetti and the long celebration. Every package and dock always shows a shape symbol
   (●■▲◆), so colour is never the only cue. "Larger shape symbols" enlarges them.

## Tile rotation

| Phase | What happens | Value |
|---|---|---|
| Touch down | The tile sinks into its lip and pre-tilts clockwise. Soft tap click, 6 ms haptic. | tilt 0.06 turn, eased at 30/s |
| Release (tap) | Logical rotation is applied. The visual snaps with an ease-out-back, a scale pop and a mechanical "tick-clack". | `ROT_TIME` 140 ms, pop ±6 %, haptic 10 ms |
| Long press | Counter-clockwise rotation (same cost as clockwise). | `LONG_PRESS` 380 ms, haptic 20 ms |
| Rapid taps | The next animation starts from the *current* visual angle and retargets. | no queueing, no lost taps |
| Locked tile | Horizontal nudge and a low "thunk". The first time, a banner explains pins. | shake decays in about 0.3 s |

Raised tiles (rotatable) have a 6.5 % lip and a drop shadow. Pinned belts sit almost flush, on a
tinted face, with a pin that turns with the belt. Sources and docks are flat.

## Running the factory

* **Run** plays a rising sweep. Conveyors under packages start rolling: rollers move only on
  cells a package has visited.
* **Path illumination:** every visited cell glows in the colour of the package that crossed it,
  fading to a steady tint. You can read the route at a glance.
* **Package motion:** packages move at constant speed while they keep moving. They ease in when
  starting and ease out when stopping or waiting, so there is no stop-start at every cell. Each
  package has a contact shadow, a darker base and tape, and always shows its symbol.
* **Delivery:** the dock pops, fills with the package colour and throws a small burst, with a
  bell chime and a 16 ms haptic.
* **Speed ×2** keeps the same motion curves at half the step time.

## Failure

When a run fails, the play screen:

* Names the package and the cause, e.g. *"The orange package hit a belt that isn't connected on
  that side."*, plus one actionable tip.
* Marks the failure tile with a pulsing red ring and a ✕ badge.
* Tints that package's path red, so you can see where the route went wrong.
* Never reveals the solution and never opens a modal. Retries are unlimited and free.

## Success

1. After the last delivery there is a short pause of 180 ms.
2. A light wave runs along every travelled belt in delivery order. Docks fill, confetti bursts
   from each dock, and a success ring expands from the board plate.
3. The default length is 1.2 s, set by the `celebration_ms` experiment (1200 or 800). **Tap the
   board to skip.** Back also skips.
4. The result card appears. The title is "Perfect!" at par or "Delivered!" otherwise. Stars are
   revealed one by one with rising chimes. The rotation count and par are shown, plus one line
   of context (perfect, personal best, or the par to aim for).
5. **Next** is the largest element on the card. Replay, Challenge, Share and Home are secondary.

## Audio and haptics

All sound is synthesised at runtime (`scripts/core/sfx.gd`), so there are no assets to license.
Sound effects, music and vibration each have their own setting.

| Event | Sound | Haptic |
|---|---|---|
| Touch | tap click | light (6 ms) |
| Rotate | tick-clack (cw higher, ccw lower) | tick (10 ms) |
| Locked | low thunk | warn (35 ms) |
| Run | rising sweep | — |
| Delivery | two-note chime | medium (16 ms) |
| Fail | falling triangle sweep | warn |
| Level complete | four-note arpeggio | success (18 ms + 30 ms) |
| Perfect | five-note arpeggio | success |
| Star reveal | bell, pitch +12 % per star | — |
| Hint | two soft notes | — |
| Achievement | two-note fanfare | — |

**Music** is a 16-second ambient pad loop (Cmaj7 – Am7 – Fmaj7 – G6) with sparse pentatonic
plucks at −17 dB. It is generated once on a worker thread, so startup is not blocked, and loops
seamlessly. Haptics use `Input.vibrate_handheld`, which is a no-op on desktop.

> **Not verified on a device:** haptic strength, audio mix on phone speakers and touch latency
> need a playtest on real Android and iOS hardware (see [known-limitations](known-limitations.md)).

## Onboarding

Levels 1–5 use an interactive coach (`tutorial_flow` = `coach`, the default):

| Level | Teaches | Coach behaviour |
|---|---|---|
| 1 First Tap | rotate a conveyor | A finger points at the tile to turn. |
| 2 Bend | connect a path | A finger follows the next useful tile until the path works. |
| 3 Detour | deliver a package | A finger shows the first move only, then the player plans. |
| 4 Pinned | locked belts | Text only. Tapping a pin explains it. |
| 5 Convoy | planning and par | Text only. The star preview shows the par stakes. |

When the path is solved, the banner turns green ("Path ready!") and the Run button pulses.
Analytics records `tutorial_start` on level 1 and `tutorial_complete` on the first clear of level 5.

## Hints

The hint system uses the solver's verified optimal solution from the current board, so a hint
can never suggest a wasted or illegal move:

1. **Area:** a 3×3 region containing a belt that needs turning.
2. **Tile:** the exact belt.
3. **Rotation:** the direction and number of taps.

Asking again about the same suggestion goes one step deeper. After you move on, the next
suggestion starts at step 1 again. Each step counts as a hint used. Hints are disabled on
ranked dailies and friend challenges. A unit test follows hints from the start of six levels and
checks that they always reach par.

## Rendering architecture (performance)

Each tile is its own CanvasItem: a base node plus a rotating belt node.

* Rotation, press, pop, shake and the intro are **transforms**, so they never re-record draw
  commands.
* A tile redraws only when its appearance signature changes: glow level, dock fill, source
  count, or rollers moving under a package.
* `StyleBoxFlat` objects are cached with quantised alpha and radius.

Measured numbers are in [performance.md](performance.md).
