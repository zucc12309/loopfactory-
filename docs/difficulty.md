# Difficulty model and campaign curve

Minimum rotations (par) alone predicts human difficulty poorly. A par-8 puzzle with one obvious
route is easier than a par-6 puzzle where two routes compete for a junction. The model in
`packages/engine/src/difficulty.ts` combines six measurable signals.

| Signal | Meaning | Weight |
|---|---|---|
| `par` | minimum rotations (solver-verified) | 1.0 |
| `searchBits` | log2 of the configuration space the player can reach (Π period of rotatable tiles) | 0.25 |
| `routes − 1` | extra independent routes to plan | 2.5 |
| `interactions` | cells used by more than one colour, plus half the waiting ticks (cap 3) | 1.2 |
| `mechanics` | distinct mechanics present: corner, junction, crossing, pin, convoy, colours | 0.8 |
| `solverBits` | log2 of solver search nodes, a proxy for backtracking | 0.6 |

`estimate = Σ weight × signal`. The weights were tuned by hand so that the intended order of the
original campaign scored monotonically within each world. They are a **hypothesis**: re-fit them
against analytics (time to solve, retries, hint use and abandonment per `level_id`) once real
players exist. See [analytics.md](analytics.md).

## Automated checks (`npm run levels:build` / `levels:check`, CI)

* **Spike check:** no level may exceed the hardest of the previous three by more than
  `SPIKE_LIMIT` = 9.
* **Mechanics check:** no level may introduce more than `MAX_NEW_MECHANICS` = 2 mechanics the
  player hasn't seen. A colour count counts as new only the first time.
* Every level must be valid and not start solved. Its par must be the true minimum, and its
  stored solution must pass `verifyReplay`.
* The build writes [difficulty-report.md](difficulty-report.md), and CI fails if that report is
  stale.

## What the audit found and what changed

* **Content bug:** level 26 (*Interchange*) carried the tip "Packages wait their turn at busy
  tiles", but its solution never makes a package wait (`waits = 0`). The mechanic was being
  "taught" on a level that doesn't show it.
* **New transition level `x26` Right of Way** (opens *Neon Circuit*). This is a hand-made 5×5
  crossing whose solution makes the orange convoy wait while blue crosses. It is the only new
  idea in the level (estimate 16, par 3), and it now carries the right-of-way tip. A unit test
  asserts that its solution contains a `waiting` frame.
* **New transition level `x31` Third Shift** (opens *Space Logistics*). It is the easiest
  three-colour layout found by searching expert seeds 2000–2400 (estimate 31.9, par 10) and comes
  before *Tri-Color* (35.7).
* The **Plant Director** achievement threshold moved from 34 to 36, so it still means "every
  campaign puzzle".
* Levels 10–13 deliberately dip (estimates 6.7–10.5) as a breather at the start of *Candy
  Factory*. The model flags no spike there.

Existing players keep their progress: progress is keyed by level id, and new ids don't collide.
Displayed level numbers after position 26 shift by one, then by two after position 32.

## Endless difficulty

Endless tiers ramp after 5, 15 and 35 solves. The `difficulty_ramp` experiment's `gentle`
variant stretches each tier by 1.5×. Every generated puzzle passes the same validity checks as
campaign content. A property test generates 1,000 puzzles across the small tiers and checks
validity, solvability, replay-verified par, the solver budget, seed reproducibility and that no
layout is duplicated.
