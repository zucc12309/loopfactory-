# Character system testing

All automated suites run with `./scripts/test-game.sh` (unit tests headless; the two scene
suites under Xvfb with the GL renderer). Results below were produced on 2026-10-15 in this
repository's Linux container; none of them ran on a phone.

| Suite | File | Result |
|---|---|---|
| Crew unit tests | `apps/game/tests/test_crew.gd` | 18 tests, all pass (whole Godot unit suite: 56 tests / 7,481 assertions, 0 failed) |
| Crew scene tests | `apps/game/tests_ui/crew_ui_tests.gd` | 121 checks, 0 failed |
| Existing UI tests (with characters on) | `apps/game/tests_ui/ui_tests.gd` | 281 checks, 0 failed |
| Character sheet render | `apps/game/tests_ui/crew_sheet.gd` | produces `docs/assets/crew-sheet.png` (visual review) |
| Board benchmark | `apps/game/tests_ui/bench_board.gd` | see [performance.md](performance.md) |

## The 15 required checks

| # | Requirement | How it is tested |
|---|---|---|
| 1 | Animations don't affect deterministic results | Unit: every pose is computed for every package of every frame of six solved campaign levels; the simulation result is byte-identical before/after and on re-simulation. Scene: the same level run with characters on and off gives the same success, ticks, delivered count, failure reason, number of `package_delivered` signals and playback length (±0.06 s). |
| 2 | Correct colour and destination identity | Unit: colours 0–3 map to Bloop, Zip, Glitch, Mochi, exactly one each. Scene: a rendered body pixel equals the package colour and the symbol centre is white, for all four. |
| 3 | Undo and Reset restore visual state | Scene: after a failed run, an edit, an undo and a reset each clear the failing character's reaction and the failure mark; after reset every belt's settled angle matches the model. (This found a bug: Reset did nothing after a failed run with no moves. Fixed.) |
| 4 | Backgrounding doesn't corrupt animation state | Scene: mid-run the app receives pause/resume notifications and a single 45-second frame gap; the run finishes with the identical result and finite board time. |
| 5 | Saved games load without errors | Unit: a pre-crew save (no `crew` block, no crew settings) loads, gains defaults and keeps its progress byte-identical. |
| 6 | Compact boards remain readable | Scene: the 6×7 board on 720×960 switches to compact characters with a symbol at least 9 px across; the 4×4 board on 720×1280 uses full detail. Existing layout tests (5 aspect ratios) pass with characters on. |
| 7 | Cosmetics never hide essential symbols | Scene: every look on every package, with and without "Larger shape symbols", at full and compact size (48 renders) — the symbol area (radius 0.27 of the body) is pixel-identical (≤ 3/255 rasteriser rounding) to the same character without a look; compact characters ignore looks entirely. |
| 8 | Daily results unchanged | Unit: a daily completed under `hybrid` and `minimal` produces identical moves, stars, stored result and submitted move list. |
| 9 | Reduced motion works | Unit: with motion off every state of every character is static over time (no offset, scale, rotation, glitch, foot tap) and idle/waiting expressions don't flicker. Scene: Reduce motion and the Character animations setting both stop board motion but keep characters. |
| 10 | Offline gameplay remains functional | All crew data and dialogue ship in the app; the scene suites run with no API server running (every request fails, so the client is offline) and exercise play, The Crew, Home and the share card. |
| 11 | Existing progress compatible | Unit: an old save with 10 solved levels keeps its progress and receives exactly the looks it already earned (retroactive unlocks). |
| 12 | Collection saves and restores | Unit: equip rules (locked / other character's looks refused), save → reload round trip, unknown references dropped. Scene: equip from the detail page, save, reload from disk, the board uses the look. |
| 13 | Missing assets fall back gracefully | Unit: a missing roster file falls back to built-in definitions; an unknown character id draws as a generic package with valid poses; stale cosmetic ids are removed on load. |
| 14 | Repeated Run/Reset doesn't duplicate animations | Scene: Run/Stop ×12 at random frame gaps ends with no playback, no celebration, zero characters drawn, no particle build-up and edit controls back. |
| 15 | Performance on lower-end Android | Desktop benchmark only (software rendering). Characters cost the same as classic packages while running and ≈ 0.25 ms more while idle. **Not measured on a phone** — see manual tests. |

Additional automated checks: unlock rules are reachable with current content (counts ≤ 36
levels / 108 stars, worlds exist) and follow real progress; dialogue lines are short, unique,
well-formed, cover every required event and every Dr. Rix / world introduction; dialogue
selection rules (priority, conditions, cooldown, show-once, probability); translation fallback
by id; moments detected only from real results (and from constructed frames); remote flags and
presentation variants switch exactly the intended features; tapping a source no longer shows the
"Pinned belt" coach.

## Manual device tests

Not run — no device or emulator was available in this environment. Before release, on at least
one low-end (2–3 GB RAM, Mali/Adreno 5xx class) and one mid-range Android phone:

| Area | Steps | Pass criteria |
|---|---|---|
| Frame rate | Play c34 (6×7) and c20 with characters on; run at normal and ×2 speed; let the celebration play | No visible stutter; Android GPU profiler bars under 16 ms; compare with Character packages off |
| Readability | Play the 6×7 levels on the smallest supported screen in daylight | Every symbol identifiable at a glance; faces never hide belts or docks |
| Touch | Rapidly tap sources and belts during idle | Pokes respond on the same frame; no missed rotations |
| Lifecycle | Background the app mid-run and mid-celebration (home button, incoming call), return after 5 s and after 10 min; kill and relaunch | Run/celebration resume or finish cleanly; resume restores rotations; no stuck reactions |
| Reduced motion | Enable Reduce motion and Android "Remove animations" | Characters still; expressions still change |
| Audio / haptics | Poke characters, tap Captain Naps, complete a level with sound/vibration on and off | Sounds are subtle and respect settings; haptics are light |
| Dialogue pacing | Play 10 levels in one session | Captain Naps speaks rarely; nothing blocks Next; bubble dismiss works |
| Collection | Unlock a look (fresh install, solve 5 levels), equip it, kill the app, relaunch | Toast once, accent Crew button, look persists |
| Battery / heat | 20 minutes continuous play | No noticeable difference vs. Character packages off |
| Share card | Save a daily share image, view it in WhatsApp / Instagram / Discord previews | Characters and text crisp; nothing private shown |
