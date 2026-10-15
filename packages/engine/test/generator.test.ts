import { describe, expect, it } from 'vitest';
import { DIFFICULTIES, validateBoard } from '../src/level';
import { GENERATOR_VERSION, TIERS, generateLevel } from '../src/generator';
import { fnv1a32, Rng } from '../src/rng';
import { applyMoves } from '../src/level';
import { isSolved } from '../src/simulation';
import { verifyReplay } from '../src/replay';

describe('rng', () => {
  it('is reproducible and well distributed', () => {
    const a = new Rng(42);
    const b = new Rng(42);
    const seqA = Array.from({ length: 20 }, () => a.nextU32());
    expect(Array.from({ length: 20 }, () => b.nextU32())).toEqual(seqA);
    const r = new Rng(1);
    const buckets = [0, 0, 0, 0];
    for (let i = 0; i < 4000; i++) buckets[r.int(4)]!++;
    for (const n of buckets) expect(n).toBeGreaterThan(850);
  });
  it('hashes strings with FNV-1a', () => {
    expect(fnv1a32('')).toBe(0x811c9dc5);
    expect(fnv1a32('a')).toBe(0xe40c292c);
    expect(fnv1a32('daily-2026-10-15')).toBe(fnv1a32('daily-2026-10-15'));
  });
});

describe('generator', () => {
  for (const tier of DIFFICULTIES) {
    it(`produces valid, verified ${tier} levels`, () => {
      for (let seed = 100; seed < 115; seed++) {
        const lvl = generateLevel(seed, tier);
        expect(lvl, `seed ${seed}`).not.toBeNull();
        validateBoard(lvl!);
        const start = lvl!.tiles.map((t) => t.r);
        expect(isSolved(lvl!, start)).toBe(false);
        expect(applyMoves(lvl!, lvl!.solution.moves)).toEqual(lvl!.solution.rotations);
        expect(isSolved(lvl!, lvl!.solution.rotations)).toBe(true);
        expect(lvl!.par).toBe(lvl!.solution.moves.length);
        expect(lvl!.par).toBeGreaterThanOrEqual(TIERS[tier].minRotations);
        expect(lvl!.par).toBeLessThanOrEqual(TIERS[tier].maxRotations);
        expect(lvl!.generator).toEqual({ version: GENERATOR_VERSION, seed, tier });
        expect(verifyReplay(lvl!, lvl!.solution.moves).valid).toBe(true);
      }
    });
  }
  it('is deterministic per seed', () => {
    expect(JSON.stringify(generateLevel(77, 'hard'))).toBe(JSON.stringify(generateLevel(77, 'hard')));
    expect(JSON.stringify(generateLevel(77, 'hard'))).not.toBe(JSON.stringify(generateLevel(78, 'hard')));
  });
});

describe('replay verification', () => {
  const lvl = generateLevel(5, 'medium')!;
  it('accepts a valid replay and scores by move count', () => {
    const v = verifyReplay(lvl, lvl.solution.moves);
    expect(v).toEqual({ valid: true, rotations: lvl.par, error: null, failure: null });
  });
  it('rejects unsolved, illegal and oversized replays', () => {
    expect(verifyReplay(lvl, []).error).toBe('not_solved');
    const locked = lvl.tiles.findIndex((t) => t.t === 'source');
    expect(verifyReplay(lvl, [[locked, 1]]).error).toBe('illegal_move');
    expect(verifyReplay(lvl, Array.from({ length: 501 }, () => [0, 1] as [number, 1])).error).toBe('too_many_moves');
  });
  it('counts wasted rotations', () => {
    const idx = lvl.solution.moves[0]![0];
    const padded: [number, 1 | -1][] = [[idx, 1], [idx, -1], ...lvl.solution.moves];
    expect(verifyReplay(lvl, padded).rotations).toBe(lvl.par + 2);
  });
});
