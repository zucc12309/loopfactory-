# Upgrade audit — premium gameplay, retention & sharing

Audit date: 2026-10-15 · Baseline commit `71f1895` · Auditor: engineering (Claude Code session)

This audit was done by reading the whole repository and running every automated suite **before**
changing code. The "Status after upgrade" column links to what was actually changed; anything not
marked done is still open (see [known-limitations.md](known-limitations.md)).

## 1. Current architecture (verified, not assumed)

| Layer | Actual technology | Notes |
|---|---|---|
| Game client | **Godot 4.3, GDScript**, `gl_compatibility` renderer, 720×1280 canvas, `canvas_items` + `expand` stretch, portrait | No `.tscn` scenes for UI: every screen is built in code (`scripts/ui/screens/*.gd`) from shared tokens in `style.gd`. All drawing of the board is immediate-mode `_draw()` in `board_view.gd`. |
| Game rules | `packages/engine` (TypeScript, canonical) + a GDScript port (`apps/game/scripts/engine`) | Deterministic tick simulation, exact min-rotation solver, seeded generator `gen-1`. Parity proven with 1,794 fixture assertions. |
| State | `LFGameState` (pure, unit-tested) wrapped by the `Game` autoload | Atomic save (tmp → bak → rename + sha256), saved on every move and on pause/focus-out/close. |
| Sync | `Net` autoload, op queue (opId, coalescing, exponential backoff) | Merge rules in `docs/sync.md`. |
| Backend | Node 22, Express, Zod, Prisma 6, PostgreSQL | Route registry → validation + OpenAPI 3.1. Server re-simulates every submitted replay. |
| Daily | Seed = HMAC(secret, UTC date); solution stripped from the public payload | Offline practice puzzle is generated locally and is never ranked. |
| Leaderboards | daily, weekly (ISO week), global (campaign) | Lower is better; only server-verified rotations count. |
| Analytics | Consent-gated client adapter (PostHog batch API), 12 events | Off by default; no provider key configured. |
| Audio | Procedurally synthesised SFX (no asset licensing) | No music. |

### Screen / state map

```
splash → home ─┬─ play (campaign | endless | daily | offline_daily)
               ├─ levels → play
               ├─ daily → play (daily | offline_daily)
               ├─ profile
               └─ settings
play: edit ──Run──▶ playback ──success──▶ win overlay ─Next──▶ play(next)
                     │        └─fail────▶ toast + highlighted cell ─▶ edit
                     └─Stop─────────────▶ edit
```

## 2. Baseline test results (executed 2026-10-15)

| Suite | Result |
|---|---|
| Engine (vitest) | 35/35 passed |
| Godot headless (`scripts/test-game.sh`) | 26 tests, 1,794 assertions, 0 failed |
| API integration (vitest + local PostgreSQL 16) | 35/35 passed |

## 3. Critical issues (P0)

| # | Issue | Evidence | Status after upgrade |
|---|---|---|---|
| C1 | **Failure toast covers the board.** The toast is positioned 260 px above the bottom, which on most boards lands on the lower rows — exactly where the highlighted failure cell often is. | `docs/screenshots/fail.png` | Fixed: failure explanation is an inline banner above the board; toasts moved to the top edge. UI test asserts no failure modal and banner/board never overlap on 5 aspect ratios. |
| C2 | Off-board failures highlight nothing (`_advance_frame` sets the cell to −1). The player gets no location. | `board_view.gd` `_advance_frame` | Fixed: the failing package's last cell and its travelled path are highlighted. |
| C3 | Generic failure copy ("A package…") — never says which package. | `play.gd FAIL_TEXT` | Fixed: copy names the package colour + shape and the cause. |
| C4 | Package identity relies on colour unless the colourblind toggle is on. | `board_view.gd` | Fixed: shape symbols are always drawn; the setting now enlarges them. |

No crashes, save-corruption paths or unplayable levels were found: every curated level is solved by
the solver in tests, and saves are checksummed with a backup fallback.

## 4. Visual and usability issues

* **Tile rotation** uses exponential smoothing (`lerp` × 16/s): it never overshoots or "snaps",
  and the tap only reacts on release, so the first ~100 ms after touch show only a 0.92 scale.
* **Packages stop at every cell** (smoothstep per tick), giving a stop-start gait at all speeds.
* **No path illumination** while running, no destination reaction beyond a ring, no completion
  moment: the win card appears 0.45 s after the last frame.
* **Win card** gives equal weight to Home and Next; there is no replay or challenge action.
* **Locked vs movable** tiles differ only by a 3.5 % darker background and a small pin.
* **Hint** jumps straight to "rotate this tile ×N" — no progressive help.
* **Tutorial** exists only for level 1 (a finger on one tile).
* **Empty 70 px tip row** is reserved even when a level has no tip, pushing the board down.
* **Share** copies text only; no image, no challenge, no code.

## 5. Performance risks

* The GDScript solver runs on the main thread; expert hints take tens of ms on desktop. Hints are
  user-initiated, so this is acceptable but must be profiled on a low-end phone.
* `board_view._process` iterates every tile each frame and redraws continuously while anything
  animates. Boards are ≤ 7×7 (49 tiles) so cost is small; idle boards stop redrawing.
* `low_processor_mode` is on — good for battery; animations request redraws explicitly.
* No physical device was available: frame-rate and battery claims cannot be verified here.

## 6. Content & difficulty

* 34 curated levels in five tiers. The curve **dips**: levels 10–13 are "beginner" after easy
  levels 5–9, and level 26 introduces queueing/priority and level 31 introduces a third colour
  with no transition level.
* Difficulty labels are based on a generator score (par + tile counts), not on search-space size
  or interacting routes.
* The generator was verified on fixtures, not at scale (no 1,000-puzzle property test).

## 7. Retention / sharing gaps

Daily challenge works (official vs offline practice is honest). Missing: attempts tracking, image
result card, friend challenges, replays, worlds/themes, experiments/feature flags, and several
analytics events (first launch, tutorial, challenge funnel, session length, interruptions).

## 8. Recommended improvements & priorities

| Priority | Work | Outcome |
|---|---|---|
| P0 | C1–C4 above | Done |
| P1 | Eased rotation with press pre-tilt and snap; continuous package motion; path glow; dock reactions; 1.2 s skippable celebration; richer SFX, music toggle, haptic patterns | Done ([game-feel.md](game-feel.md)); feel not verified on a phone |
| P2 | Interactive onboarding for levels 1–5; three-step hints from the verified solution; difficulty model with spike checks; transition levels | Done ([difficulty.md](difficulty.md)) |
| P3 | Five themed worlds; 1,000-puzzle generator validation; duplicate detection | Done |
| P3b | Renderer: per-tile canvas items | Done — ~4× less CPU per frame ([performance.md](performance.md)) |
| P4 | Friend challenges (server-verified), share card PNG + code, replay viewer, daily attempts | Done; native share sheet, app/universal links and video export are **not** done ([sharing.md](sharing.md)) |
| P5 | Analytics taxonomy, deterministic experiment bucketing, documented retention queries | Done ([analytics.md](analytics.md), [experiments.md](experiments.md)); queries not run — no analytics project connected |

Monetization was intentionally not touched.

## 9. Results after the upgrade (executed 2026-10-15)

| Suite | Before | After |
|---|---|---|
| Engine (vitest) | 35 | **41** (difficulty model, 1,000-puzzle generator property test) |
| Godot unit tests | 26 tests / 1,794 assertions | **38 tests / 4,053 assertions** |
| Godot UI scene tests (new) | — | **281 checks** on 5 aspect ratios, rapid taps, failure and celebration flows |
| API integration | 35 | **41** (friend challenges) |
| Client ↔ API E2E | 16 checks | **21 checks** (friend challenge round trip) |
| Board CPU per frame, 6×7 board (desktop, software GL) | p50 5.26 ms | **p50 1.30 ms** |

All pass, along with typecheck, lint, `levels:check`, `fixtures:check` and the OpenAPI check.
Screenshots in [screenshots/](screenshots/) were regenerated from the QA tour after the changes.
Not done here: anything needing a physical device, store or analytics credentials, or production
deployment ([known-limitations.md](known-limitations.md)).
