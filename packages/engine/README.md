# @loopfactory/engine

The **canonical** Loop Factory rules: tiles and connection masks, the deterministic tick
simulation, the minimum-rotation solver, the `gen-1` procedural generator and replay verification.
Pure TypeScript, no dependencies. Used by the API (score verification, daily generation) and by the
level tooling; mirrored on device by `apps/game/scripts/engine`.

```ts
import { generateLevel, simulate, solve, verifyReplay, renderAscii } from '@loopfactory/engine';

const level = generateLevel(42, 'medium')!;      // deterministic per (seed, tier)
console.log(renderAscii(level));                  // human-readable board
const res = solve(level);                         // exact minimum rotations
verifyReplay(level, res.moves);                   // { valid: true, rotations: level.par, ... }
```

| File | Contents |
|---|---|
| `src/tiles.ts`, `src/directions.ts` | masks, rotation, cost |
| `src/simulation.ts` | tick rules (see `docs/gameplay-rules.md`) |
| `src/solver.ts` | bounded path-constrained branch & bound, hints |
| `src/generator.ts` | tiers and generation pipeline |
| `src/ascii.ts` | authoring format for curated levels |
| `src/replay.ts` | authoritative replay verification |
| `levels/curated.json` | **generated** campaign (`npm run levels:build`) |

Tests: `npm test -w @loopfactory/engine` (includes a brute-force check of solver optimality).
Changing behaviour? Update the GDScript port and run `npm run fixtures:build`.
