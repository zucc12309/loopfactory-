import { describe, expect, it } from 'vitest';
import { parseAscii } from '../src/ascii';
import { generateLevel } from '../src/generator';
import { applyMoves, type Board } from '../src/level';
import { isSolved } from '../src/simulation';
import { hint, hintOutcome, solve } from '../src/solver';
import curated from '../levels/curated.json' with { type: 'json' };
import type { Level } from '../src/level';
import { PERIOD, isRotatable, rotationCost } from '../src/tiles';

/** Exhaustive minimum over every orientation combination (only feasible for tiny boards). */
function bruteForce(board: Board): number {
  const start = board.tiles.map((t) => t.r);
  const idx = board.tiles.map((t, i) => (isRotatable(t) ? i : -1)).filter((i) => i >= 0);
  let best = Infinity;
  const rot = start.slice();
  const rec = (k: number, cost: number) => {
    if (cost >= best) return;
    if (k === idx.length) {
      if (isSolved(board, rot)) best = cost;
      return;
    }
    const i = idx[k]!;
    const t = board.tiles[i]!;
    for (let r = 0; r < PERIOD[t.t]; r++) {
      rot[i] = r;
      rec(k + 1, cost + rotationCost(t, start[i]!, r));
    }
    rot[i] = start[i]!;
  };
  rec(0, 0);
  return best === Infinity ? -1 : best;
}

describe('solver', () => {
  it('solves a simple board with the minimum rotations', () => {
    const b = parseAscii('S1a I0 L1 .\n.  .  L2 Da');
    const res = solve(b);
    expect(res.status).toBe('solved');
    expect(isSolved(b, res.rotations!)).toBe(true);
    expect(applyMoves(b, res.moves)).toEqual(res.rotations);
    expect(res.moves.length).toBe(res.minCost);
  });

  it('reports unsolvable boards', () => {
    const b = parseAscii('S1a # Da');
    expect(solve(b).status).toBe('unsolvable');
  });

  it('reports budget exhaustion instead of guessing', () => {
    const lvl = generateLevel(7, 'expert')!;
    const res = solve(lvl, lvl.tiles.map((t) => t.r), { maxNodes: 3 });
    expect(res.status).toBe('budget_exceeded');
  });

  it('matches brute force minimum on small generated boards', () => {
    let checked = 0;
    for (let seed = 1; seed <= 60 && checked < 25; seed++) {
      const lvl = generateLevel(seed, 'beginner');
      if (!lvl) continue;
      const rotatable = lvl.tiles.filter(isRotatable).length;
      if (rotatable > 9) continue;
      expect(solve(lvl).minCost, `seed ${seed}`).toBe(bruteForce(lvl));
      checked++;
    }
    expect(checked).toBeGreaterThan(10);
  });

  it('gives hints that make progress towards a solution', () => {
    const lvl = generateLevel(11, 'easy')!;
    let rot = lvl.tiles.map((t) => t.r);
    let steps = 0;
    while (!isSolved(lvl, rot) && steps < 50) {
      const h = hint(lvl, rot);
      expect(h).not.toBeNull();
      rot = applyMoves(lvl, Array.from({ length: h!.taps }, () => [h!.tile, h!.dir] as [number, 1 | -1]), rot);
      steps++;
    }
    expect(isSolved(lvl, rot)).toBe(true);
    expect(hint(lvl, rot)).toBeNull();
  });

  it('never certifies a budget-limited solution as optimal (audit reproducer: expert seed 2, 80 nodes)', () => {
    const lvl = generateLevel(2, 'expert')!;
    const start = lvl.tiles.map((t) => t.r);
    const bounded = solve(lvl, start, { maxNodes: 80 });
    expect(bounded.status).toBe('feasible');
    expect(bounded.optimal).toBe(false);
    expect(isSolved(lvl, bounded.rotations!)).toBe(true); // still a verified solution
    const full = solve(lvl, start);
    expect(full.status).toBe('solved');
    expect(full.optimal).toBe(true);
    expect(full.minCost).toBe(18);
    expect(full.minCost).toBe(lvl.par);
    expect(bounded.minCost).toBeGreaterThanOrEqual(full.minCost); // an upper bound, never below optimum
  });

  it('feasible results only arise when the budget ran out', () => {
    for (let seed = 1; seed <= 30; seed++) {
      const lvl = generateLevel(seed, 'hard');
      if (!lvl) continue;
      const res = solve(lvl, lvl.tiles.map((t) => t.r));
      expect(res.status, `seed ${seed}`).toBe('solved');
      expect(res.optimal).toBe(true);
    }
  });

  it('all 36 curated pars are proven optimal', () => {
    const levels = (curated as unknown as { levels: Level[] }).levels;
    expect(levels.length).toBe(36);
    for (const l of levels) {
      const res = solve(l, l.tiles.map((t) => t.r), { maxNodes: 500_000 });
      expect(res.status, l.id).toBe('solved');
      expect(res.minCost, l.id).toBe(l.par);
    }
  });

  it('hintOutcome distinguishes solved, exhausted, unsolvable and a real hint', () => {
    const lvl = generateLevel(11, 'easy')!;
    const start = lvl.tiles.map((t) => t.r);
    const h = hintOutcome(lvl, start);
    expect(h.kind).toBe('hint');
    if (h.kind === 'hint') expect(h.hint.optimal).toBe(true);
    const solvedRot = solve(lvl, start).rotations!;
    expect(hintOutcome(lvl, solvedRot).kind).toBe('solved');
    expect(hintOutcome(generateLevel(7, 'expert')!, generateLevel(7, 'expert')!.tiles.map((t) => t.r), { maxNodes: 3 }).kind).toBe('exhausted');
    expect(hintOutcome(parseAscii('S1a # Da'), [0, 0, 0]).kind).toBe('unsolvable');
    expect(hint(lvl, solvedRot)).toBeNull();
  });

  it('a hint from an unproven solution is flagged and still leads to a working board', () => {
    const lvl = generateLevel(2, 'expert')!;
    let rot = lvl.tiles.map((t) => t.r);
    const first = hintOutcome(lvl, rot, { maxNodes: 80 });
    expect(first.kind).toBe('hint');
    if (first.kind === 'hint') expect(first.hint.optimal).toBe(false);
    let steps = 0;
    while (!isSolved(lvl, rot) && steps < 60) {
      const h = hint(lvl, rot, { maxNodes: 80 });
      if (!h) break;
      rot = applyMoves(lvl, Array.from({ length: h.taps }, () => [h.tile, h.dir] as [number, 1 | -1]), rot);
      steps++;
    }
    expect(isSolved(lvl, rot)).toBe(true);
  });
});
