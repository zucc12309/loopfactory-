# Gameplay rules (normative)

These rules are implemented identically by `packages/engine` (TypeScript, canonical — used by the
server, level tooling and tests) and `apps/game/scripts/engine` (GDScript — used on device).
`apps/game/tests/test_parity.gd` replays ~1,700 assertions of fixtures generated from the TS engine
and requires byte-identical results (RNG streams, every simulation frame, solver node counts, hints,
complete generated levels).

## Board

* Grid `width × height` (2–12 each). Tiles are stored row-major; a tile's **ID is its index**.
* Directions: `NORTH=0, EAST=1, SOUTH=2, WEST=3`; masks use `bit(d) = 1 << d` (N=1, E=2, S=4, W=8).
* Orientation `r` = clockwise quarter turns from the base orientation. Rotating a mask clockwise:
  `((m << 1) | (m >> 3)) & 15`.

| Type | Base mask (r=0) | Input mask | Output mask | Rotatable | Period |
|---|---|---|---|---|---|
| empty, blocked | 0 | 0 | 0 | no | 1 |
| straight | N\|S | mask | mask | yes | 2 |
| corner | N\|E | mask | mask | yes | 4 |
| tee (junction) | N\|E\|S | mask | mask | yes | 4 |
| cross | all | all | all | no (symmetric) | 1 |
| source | — | 0 | bit(r) | no | 4 |
| dest (dock) | all | all | 0 | no | 1 |

Any straight/corner/tee may be **locked** (`l: true`): shown with a pin, cannot be rotated.
Sources and docks carry a color `c ∈ 0..3`; sources emit `n` packages (default 1).

Future tile types (splitter, switch, portal, one-way gate, timed gate, color filter) fit the same
model: separate input/output masks plus optional per-tile state; none are implemented yet.

## Player actions

* **Tap** → rotate clockwise. **Long-press** (0.42 s) → rotate counter-clockwise. Each counts as one
  rotation. Locked/fixed tiles give haptic + visual feedback but do not change.
* **Undo** pops the last rotation; **Reset** restores the starting orientations and clears history.
* **Run** simulates the current board; **Pause/Speed/Stop** control playback only (never results).
* **Hint** highlights the first tile along an optimal route (from the *current* board) that is not
  yet in its solved orientation, with direction and remaining taps. Hints are disabled for the
  ranked daily challenge.

The **rotation count** is the number of rotations in the move history (undo removes one).

## Simulation (deterministic ticks)

Tick 0: every source with packages left spawns one package **on its own cell**, facing its
orientation, in tile-index order (package IDs increase in spawn order).

Each subsequent tick:

1. **Intent.** Each package tries to move one cell in its travel direction `d`.
   * Leaving the board → `off_board` failure.
   * Target input mask lacks the entry side `opposite(d)` → `disconnected` failure
     (includes empty, blocked, sources).
   * Target is a dock of another color → `wrong_destination` failure.
   * Otherwise the new direction is chosen by the target tile: **straight if open, else turn right,
     else turn left** (the entry side is excluded). No exit → `disconnected`.
2. **Any failure ends the run**; the lowest package id is reported.
3. **Conflict resolution** (fixed point, deterministic):
   * Packages entering a dock never conflict (unlimited capacity).
   * Several packages targeting one cell → the lowest package id wins; the others **wait**.
   * Two packages targeting each other's cells (head-on) → both wait.
   * A package whose target cell is occupied by a waiting package also waits.
4. **Apply** all accepted moves simultaneously; packages entering their dock are delivered.
5. **Spawn**: sources whose cell is free emit their next package.
6. **Evaluate**:
   * every package delivered → **success**;
   * nothing moved and nothing spawned → `deadlock`;
   * the global state (positions, directions, remaining counts) repeats → `loop`;
   * more than `4·w·h·max(1,packages) + 50` ticks → `timeout` (unreachable in practice).

Victory therefore requires that **all** packages of **every** source reach a dock of their color;
a visually connected path is never enough. The renderer only interpolates between frames, so frame
rate cannot change outcomes.

## Scoring

* Par = the minimum number of rotations (cw or ccw, one each) from the starting board, computed
  exactly by the solver (cross-checked against brute force in `packages/engine/test/solver.test.ts`).
* Stars: 3 if rotations ≤ par, 2 if ≤ par + 3, otherwise 1. Retries are free and unlimited.

## Solver

Path-constrained backtracking with branch-and-bound (`solver.ts`): it traces each source's route
and only branches on rotatable tiles the route actually enters, and only on orientations that
accept the package from its entry side. Untouched tiles keep their current orientation. Every
candidate is confirmed with the full multi-package simulation. A node budget bounds work; when
exceeded the solver reports `budget_exceeded` (never a guess). It can also count distinct solved
configurations up to a cap — uniqueness is only ever claimed from that count.

## Procedural generation (`gen-1`)

For a `(seed, tier)`: build self-avoiding routes source → dock per color (crossing existing
perpendicular straights with cross tiles on hard/expert), optionally swap route tiles for tees that
route identically, add decoys and blocked cells, lock some route tiles, then scramble every
rotatable tile. A candidate is rejected unless the intended configuration solves, the scrambled
start does not, the solver proves solvability within budget, and par falls in the tier's range.
Everything uses the integer xorshift32 RNG, so output is reproducible across platforms. Seeds,
generator version and content version are stored with every level.

| Tier | Board | Routes | Packages/route | Extras | Par range |
|---|---|---|---|---|---|
| beginner | 4×4 | 1 | 1 | decoys | 2–5 |
| easy | 5×5 | 1 | 1–2 | locked tiles | 4–9 |
| medium | 5×6 | 2 | 1–2 | tees | 6–14 |
| hard | 6×6 | 2 | 2 | tees, crossings, locks | 8–18 |
| expert | 6×7 | 3 | 1–3 | all of the above | 10–24 |
