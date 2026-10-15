/**
 * Generates apps/game/tests/fixtures/parity.json from the canonical TypeScript engine.
 * The Godot test suite (apps/game/tests/test_parity.gd) replays every case with the GDScript port
 * and requires identical results — RNG streams, simulation outcomes and frame streams, solver
 * results (including node counts), hints, and complete generated levels.
 */
import { mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { DIFFICULTIES, Rng, applyMoves, fnv1a32, generateLevel, hint, hintOutcome, isRotatable, parseAscii, simulate, solve, verifyReplay, type Board, type Level, type Move, type SimulationResult } from '../packages/engine/src/index';

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
  solves.push({ level: lvl.id, status: s.status, optimal: s.optimal, minCost: s.minCost, rotations: s.rotations, moves: s.moves, routeOrder: s.routeOrder, nodes: s.nodes, solutionCount: s.solutionCount, solutionCountCapped: s.solutionCountCapped });
  const mid = cases[2]!;
  hints.push({ level: lvl.id, rotations: mid, hint: hint(lvl, mid) });
}

const generated: unknown[] = [];
for (const tier of DIFFICULTIES) {
  for (const seed of [1, 77, 4242]) generated.push({ tier, seed, level: generateLevel(seed, tier) });
}

// ---------------------------------------------------------------- negative paths (audit G4)
// Every failure reason, queueing/waiting and conflicting arrivals, found deterministically by
// scanning scrambled boards; the boards are stored inline so the GDScript side needs nothing else.
const boardOf = (b: Board) => ({ width: b.width, height: b.height, tiles: b.tiles });
const pool: Board[] = [...curated.levels];
for (const tier of DIFFICULTIES) for (let seed = 1; seed <= 40; seed++) {
  const g = generateLevel(seed, tier);
  if (g) pool.push(g);
}
const WANT = ['wrong_destination', 'deadlock', 'loop', 'timeout', 'off_board', 'disconnected', 'queued_success', 'queued_failure', 'conflict'] as const;
const found: Record<string, { board: unknown; rotations: number[]; result: unknown }[]> = Object.fromEntries(WANT.map((k) => [k, []]));
const nr = new Rng(77);
const tags = (res: SimulationResult): string[] => {
  const out: string[] = [];
  if (!res.success && res.reason) out.push(res.reason);
  const waited = res.frames.some((f) => f.packages.some((p) => p.state === 'waiting'));
  if (waited) out.push(res.success ? 'queued_success' : 'queued_failure');
  // Conflicting arrivals: two packages heading for the same cell in one frame.
  const conflict = res.frames.some((f) => {
    const seen = new Set<string>();
    for (const p of f.packages) {
      if (p.toX === undefined) continue;
      const k = `${p.toX},${p.toY}`;
      if (seen.has(k)) return true;
      seen.add(k);
    }
    return false;
  });
  if (conflict) out.push('conflict');
  return out;
};
// Conflicting arrivals: on some frame a package waits while another package moved INTO the cell it
// was heading for (two packages claimed one cell; the lower id won).
const hasConflict = (b: Board, res: SimulationResult): boolean => {
  for (let i = 1; i < res.frames.length; i++) {
    const prev = res.frames[i - 1]!;
    const cur = res.frames[i]!;
    const movedInto = new Set(cur.packages.filter((p) => p.state === 'moved').map((p) => p.cell));
    for (const p of cur.packages) {
      if (p.state !== 'waiting') continue;
      const before = prev.packages.find((q) => q.id === p.id);
      if (!before) continue;
      const x = (before.cell % b.width) + [0, 1, 0, -1][before.dir]!;
      const y = Math.floor(before.cell / b.width) + [-1, 0, 1, 0][before.dir]!;
      if (movedInto.has(y * b.width + x)) return true;
    }
  }
  return false;
};
for (let round = 0; round < 60 && WANT.some((k) => found[k]!.length < 3); round++) {
  for (const b of pool) {
    const rotations = b.tiles.map((t) => (isRotatable(t) ? nr.int(4) : t.r));
    const res = simulate(b, rotations);
    for (const t of tags(res)) if (found[t] && found[t]!.length < 3) found[t]!.push({ board: boardOf(b), rotations, result: summary(res) });
  }
}
// Hand-built boards for reasons the scan can't reach.
const handBoards: [string, string][] = [
  ['wrong_destination', 'S1a I1 Db'],
  ['off_board', 'S1a I0'],
  ['disconnected', 'S1a # Da'],
];
for (const [k, txt] of handBoards) {
  const b = parseAscii(txt);
  const rotations = b.tiles.map((t) => t.r);
  found[k]!.push({ board: boardOf(b), rotations, result: summary(simulate(b, rotations)) });
}
// Exhaustive search over every rotation of small templates for the rarer outcomes.
function* allRotations(b: Board): Generator<number[]> {
  const idx = b.tiles.map((t, i) => (isRotatable(t) ? i : -1)).filter((i) => i >= 0);
  const rot = b.tiles.map((t) => t.r);
  const rec = function* (k: number): Generator<number[]> {
    if (k === idx.length) {
      yield rot.slice();
      return;
    }
    for (let r = 0; r < 4; r++) {
      rot[idx[k]!] = r;
      yield* rec(k + 1);
    }
  };
  yield* rec(0);
}
const templates: [string, string, (b: Board, r: SimulationResult) => boolean][] = [
  ['loop', 'Da S2a .\nL0 T0 L0\nL0 I0 L0', (_b, r) => r.reason === 'loop'],
  ['loop', 'Da S0a .\nL0 T0 L0\nL0 I0 L0', (_b, r) => r.reason === 'loop'],
  ['conflict', 'S1a T0 S3a\n. Da .', (b, r) => r.success && hasConflict(b, r)],
  ['conflict', 'S1a T0 S3b\n. I0 .\n. Da Db', (b, r) => hasConflict(b, r)],
];
for (const [k, txt, ok] of templates) {
  const b = parseAscii(txt);
  for (const rotations of allRotations(b)) {
    const res = simulate(b, rotations);
    if (ok(b, res)) {
      found[k]!.push({ board: boardOf(b), rotations, result: summary(res) });
      break;
    }
  }
}
// Timeout: a board that would succeed, cut off by a tick limit shorter than its route.
const timeouts = curated.levels.slice(10, 13).map((l) => {
  const res = simulate(l, l.solution.rotations, { maxTicks: 3 });
  return { board: boardOf(l), rotations: l.solution.rotations, maxTicks: 3, result: summary(res) };
});
found.timeout!.push(...timeouts.filter((t) => (t.result as { reason: string }).reason === 'timeout'));
for (const k of WANT) if (found[k]!.length === 0) throw new Error(`no fixture for ${k}`);
const negative = { sims: found };

// Solver/hint outcome semantics on boards that exercise every status.
const exp2 = generateLevel(2, 'expert')!;
const exp7 = generateLevel(7, 'expert')!;
const easy11 = generateLevel(11, 'easy')!;
const unsolvable = parseAscii('S1a # Da');
const solverCases: [string, Board, number[], number][] = [
  ['feasible_unproven', exp2, exp2.tiles.map((t) => t.r), 80],
  ['proven_optimal', exp2, exp2.tiles.map((t) => t.r), 200_000],
  ['budget_exhausted', exp7, exp7.tiles.map((t) => t.r), 3],
  ['unsolvable', unsolvable, unsolvable.tiles.map((t) => t.r), 200_000],
  ['already_solved', easy11, easy11.solution.rotations, 200_000],
];
const outcomes = solverCases.map(([name, b, start, maxNodes]) => {
  const r = solve(b, start, { maxNodes });
  return {
    name, board: boardOf(b), start, maxNodes,
    solve: { status: r.status, optimal: r.optimal, minCost: r.minCost, rotations: r.rotations, nodes: r.nodes },
    hint: hintOutcome(b, start, { maxNodes }),
  };
});
// Invalid move input: both engines must reject the same move lists.
const moveBoard = curated.levels[0]!;
const fixedTile = moveBoard.tiles.findIndex((t) => !isRotatable(t));
const badMoves: [string, unknown[]][] = [
  ['out_of_range', [[moveBoard.tiles.length, 1]]],
  ['negative_index', [[-1, 1]]],
  ['bad_direction', [[moveBoard.solution.moves[0]![0], 2]]],
  ['zero_direction', [[moveBoard.solution.moves[0]![0], 0]]],
  ['fixed_tile', [[fixedTile, 1]]],
  ['valid', moveBoard.solution.moves],
];
const moves = badMoves.map(([name, mv]) => {
  let legal = true;
  try {
    applyMoves(moveBoard, mv as Move[]);
  } catch {
    legal = false;
  }
  return { name, level: moveBoard.id, moves: mv, legal, verdict: verifyReplay(moveBoard, mv as Move[]) };
});

const json = JSON.stringify({ rng, fnv, sims, solves, hints, generated, negative, outcomes, moves }) + '\n';
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
  console.log('negative cases:', Object.fromEntries(Object.entries(found).map(([k, v]) => [k, v.length])), `${outcomes.length} solver outcomes, ${moves.length} move cases`);
}
