# Loop Factory — Godot client

Godot **4.3**, GDScript, GL Compatibility renderer, portrait 720×1280 base resolution
(`canvas_items` stretch, `expand` aspect). Open this folder in the Godot editor and press ▶.

## Layout

| Path | What lives there |
|---|---|
| `scripts/engine/` | Rules engine port: `tiles.gd`, `rng.gd`, `simulation.gd`, `solver.gd`, `generator.gd` (must match `packages/engine`) |
| `scripts/core/` | Autoloads — `Game` (state + autosave), `Net` (API + sync + challenges), `Sfx` (synthesised SFX, music, haptic patterns), `Analytics` (consent-gated) — plus `game_state.gd`, `save_store.gd`, `flags.gd` (experiments), `dev_tour.gd` |
| `scripts/ui/` | Design system (`style.gd`, `icons.gd`, `icon_button.gd`), worlds/themes (`worlds.gd`), board renderer (`board_view.gd`), share card (`share_card.gd`), router (`main.gd`) |
| `scripts/ui/screens/` | `splash`, `home`, `levels`, `play`, `daily`, `challenge`, `replay`, `profile`, `settings` |
| `data/` | Curated levels and achievements — **generated**, edit `scripts/levels/curated-source.ts` instead |
| `config/client.json` | Public client config (API URL, analytics provider). Never put secrets here |
| `assets/` | App icon/splash (generated from `icon.svg`) and the Nunito font (OFL) |
| `tests/` | Headless unit tests; `tests_ui/` scene-level layout/feel tests and the board benchmark; `tests_e2e/` needs a running API |
| `export_presets.cfg` | Android and iOS presets |

## Controls

Tap = rotate clockwise · long-press = counter-clockwise · Undo / Reset / Hint / Run ·
Android back button navigates back.

## Commands

```bash
../../scripts/test-game.sh                     # unit + UI tests (fails on any GDScript error)
../../scripts/e2e.sh                           # client <-> API end to end
godot --path . -- --tour=/abs/out/dir          # screenshot every screen
godot --path . -- --challenge=ABCD2345          # open a friend challenge on launch
../../scripts/build-android.sh debug           # APK -> build/
```

## Conventions

- UI is built in code from `LFStyle` tokens; avoid ad-hoc colours.
- Never mutate rules here without changing `packages/engine` too and running
  `npm run fixtures:build` — `test_parity.gd` will fail otherwise.
- Anything that should reach the server goes through `LFGameState.enqueue()`.
