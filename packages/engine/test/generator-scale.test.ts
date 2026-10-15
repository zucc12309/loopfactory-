/**
 * Content-quality property test: 1,000 generated puzzles across the small tiers must all be valid,
 * solvable with a replay-verified solution, not start solved, not be trivial, stay within the
 * solver budget, be reproducible from their seed, and not duplicate each other's layout.
 */
import { describe, expect, it } from 'vitest';
import {
  TIERS,
  generateLevel,
  isSolved,
  simulate,
  solve,
  validateBoard,
  verifyReplay,
  type Difficulty,
  type Level,
} from '../src/index';

const PLAN: [Difficulty, number][] = [
  ['beginner', 400],
  ['easy', 350],
  ['medium', 250],
];

function layoutKey(l: Level): string {
  return `${l.width}x${l.height}:` + l.tiles.map((t) => `${t.t}${t.r}${t.c ?? ''}${t.n ?? ''}${t.l ? '!' : ''}`).join(',');
}

describe('generator at scale', () => {
  const generated: Level[] = [];
  let failures = 0;
  for (const [tier, count] of PLAN) {
    for (let seed = 1; generated.filter((l) => l.difficulty === tier).length < count; seed++) {
      const l = generateLevel(seed * 2654435761 >>> 0, tier);
      if (l) generated.push(l);
      else failures++;
      if (seed > count * 3) break;
    }
  }

  it('produces at least 1,000 puzzles', () => {
    console.log(`generated ${generated.length} puzzles, ${failures} seeds without a puzzle`);
    expect(generated.length).toBeGreaterThanOrEqual(1000);
    // A seed occasionally fails (the caller then tries seed+1); it must stay rare.
    expect(failures / (generated.length + failures)).toBeLessThan(0.05);
  });

  it('every puzzle is valid, unsolved at start, solvable and replay-verified at par', () => {
    for (const l of generated) {
      expect(() => validateBoard(l)).not.toThrow();
      const start = l.tiles.map((t) => t.r);
      expect(isSolved(l, start)).toBe(false);
      const sim = simulate(l, start, { recordFrames: false });
      expect(sim.success).toBe(false);
      expect(sim.reason).not.toBeNull();
      const cfg = TIERS[l.difficulty];
      expect(l.par).toBeGreaterThanOrEqual(cfg.minRotations);
      expect(l.par).toBeLessThanOrEqual(cfg.maxRotations);
      expect(l.solution.moves.length).toBe(l.par);
      const v = verifyReplay(l, l.solution.moves);
      expect(v.valid).toBe(true);
      expect(isSolved(l, l.solution.rotations)).toBe(true);
    }
  });

  it('par is the true minimum and the search stays within budget', () => {
    for (const l of generated.filter((_, i) => i % 5 === 0)) {
      const res = solve(l, l.tiles.map((t) => t.r), { maxNodes: TIERS[l.difficulty].solverBudget });
      expect(res.status).toBe('solved');
      expect(res.minCost).toBe(l.par);
    }
  });

  it('is reproducible from the seed', () => {
    for (const l of generated.filter((_, i) => i % 20 === 0)) {
      const again = generateLevel(l.generator!.seed, l.difficulty);
      expect(again).toEqual(l);
    }
  });

  it('has no duplicate layouts', () => {
    const keys = new Set(generated.map(layoutKey));
    expect(keys.size).toBe(generated.length);
  });

  it('one fewer rotation than par never solves (spot check of minimality)', () => {
    for (const l of generated.filter((_, i) => i % 50 === 0)) {
      const moves = l.solution.moves.slice(0, -1);
      expect(verifyReplay(l, moves).valid).toBe(false);
    }
  });
});
