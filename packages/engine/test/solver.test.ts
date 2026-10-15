import { describe, expect, it } from 'vitest';
import { parseAscii } from '../src/ascii';
import { generateLevel } from '../src/generator';
import { applyMoves, type Board } from '../src/level';
import { isSolved } from '../src/simulation';
import { hint, solve } from '../src/solver';
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
});
