/**
 * Generates apps/game/tests/fixtures/parity.json from the canonical TypeScript engine.
 * The Godot test suite (apps/game/tests/test_parity.gd) replays every case with the GDScript port
 * and requires identical results — RNG streams, simulation outcomes and frame streams, solver
 * results (including node counts), hints, and complete generated levels.
 */
import { mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { DIFFICULTIES, Rng, fnv1a32, generateLevel, hint, isRotatable, simulate, solve, type Level, type SimulationResult } from '../packages/engine/src/index';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const out = resolve(root, 'apps/game/tests/fixtures/parity.json');
const curated = JSON.parse(readFileSync(resolve(root, 'packages/engine/levels/curated.json'), 'utf8')) as { levels: Level[] };

export function frameDigest(res: SimulationResult): string {
  return res.frames
    .map((f) => `${f.tick}:${f.delivered}:` + f.packages.map((p) => `${p.id}@${p.cell}/${p.dir}/${p.state[0]}${p.toX !== undefined ? `>${p.toX},${p.toY}` : ''}`).join(','))
    .join(';');
}
const summary = (res: SimulationResult) => ({
  success: res.success,
  reason: res.reason,
  ticks: res.ticks,
  delivered: res.delivered,
  total: res.total,
  failurePackage: res.failurePackage,
  failureCell: res.failureCell,
  digest: frameDigest(res),
});

const rng = [0, 1, 42, 123456789, 4294967295].map((seed) => {
  const r = new Rng(seed);
  return { seed, values: Array.from({ length: 12 }, () => r.nextU32()), ints: Array.from({ length: 12 }, () => r.int(7)) };
});
const fnv = ['', 'a', 'loop', 'daily-2026-10-15', 'ünïcode ✓'].map((text) => ({ text, hash: fnv1a32(text) }));

const sims: unknown[] = [];
const solves: unknown[] = [];
const hints: unknown[] = [];
const rr = new Rng(2024);
for (const lvl of curated.levels) {
  const start = lvl.tiles.map((t) => t.r);
  const cases: number[][] = [start, lvl.solution.rotations];
  for (let k = 0; k < 3; k++) cases.push(lvl.tiles.map((t) => (isRotatable(t) ? rr.int(4) : t.r)));
  for (const rotations of cases) sims.push({ level: lvl.id, rotations, result: summary(simulate(lvl, rotations)) });
  const s = solve(lvl, start, { maxNodes: 200_000, countCap: 20 });
  solves.push({ level: lvl.id, status: s.status, minCost: s.minCost, rotations: s.rotations, moves: s.moves, routeOrder: s.routeOrder, nodes: s.nodes, solutionCount: s.solutionCount, solutionCountCapped: s.solutionCountCapped });
  const mid = cases[2]!;
  hints.push({ level: lvl.id, rotations: mid, hint: hint(lvl, mid) });
}

const generated: unknown[] = [];
for (const tier of DIFFICULTIES) {
  for (const seed of [1, 77, 4242]) generated.push({ tier, seed, level: generateLevel(seed, tier) });
}

const json = JSON.stringify({ rng, fnv, sims, solves, hints, generated }) + '\n';
if (process.argv.includes('--check')) {
  let current = '';
  try {
    current = readFileSync(out, 'utf8');
  } catch {
    /* missing */
  }
  if (current !== json) {
    console.error('Parity fixtures are stale. Run npm run fixtures:build');
    process.exit(1);
  }
  console.log('Parity fixtures up to date.');
} else {
  mkdirSync(dirname(out), { recursive: true });
  writeFileSync(out, json);
  console.log(`Wrote ${out}: ${sims.length} sims, ${solves.length} solves, ${hints.length} hints, ${generated.length} generated levels`);
}
