import { describe, expect, it } from 'vitest';
import { parseAscii } from '../src/ascii';
import { applyMoves, IllegalMoveError } from '../src/level';
import { simulate } from '../src/simulation';

const run = (text: string) => {
  const b = parseAscii(text);
  return simulate(b, b.tiles.map((t) => t.r));
};

describe('simulation', () => {
  it('delivers a package along a straight line', () => {
    const res = run('S1a I1 I1 Da');
    expect(res.success).toBe(true);
    expect(res.ticks).toBe(3);
    expect(res.delivered).toBe(1);
  });

  it('follows corners', () => {
    const res = run(`
      S1a L2 .
      .   L0 Da`);
    expect(res.success).toBe(true);
  });

  it('fails when a conveyor is disconnected', () => {
    const res = run('S1a I0 Da');
    expect(res.success).toBe(false);
    expect(res.reason).toBe('disconnected');
    expect(res.failureCell).toBe(1);
  });

  it('fails when a package leaves the board', () => {
    const res = run('S3a I1 Da');
    expect(res.reason).toBe('off_board');
  });

  it('fails on wrong-colored destination', () => {
    const res = run('S1a I1 Db Da');
    expect(res.reason).toBe('wrong_destination');
  });

  it('a visually connected path alone is not victory: every package must be delivered', () => {
    // Blue source exists but has no route; red route is perfect.
    const res = run(`
      S1a I1 Da
      S1b #  Db`);
    expect(res.success).toBe(false);
    expect(res.delivered).toBeLessThan(res.total);
  });

  it('emits multiple packages from one source in order', () => {
    const res = run('S1a3 I1 I1 Da');
    expect(res.success).toBe(true);
    expect(res.total).toBe(3);
    expect(res.delivered).toBe(3);
    // packages are spawned one per tick once the source cell is free
    expect(res.frames[0]!.packages.map((p) => p.id)).toEqual([0]);
    expect(res.frames[1]!.packages.map((p) => p.id)).toEqual([0, 1]);
  });

  it('resolves merge conflicts by lowest package id (others wait)', () => {
    // Blue (tile 1, id 0) and red (tile 3, id 1) reach the tee on the same tick.
    const res = run(`
      .   S2b .
      S1a T2  .
      .   I0  .
      Db  L3  Da`);
    const tick1 = res.frames[1]!.packages;
    expect(tick1.find((p) => p.id === 0)!.state).toBe('moved');
    expect(tick1.find((p) => p.id === 1)!.state).toBe('waiting');
    // Both are routed to the blue destination, so red eventually fails there.
    expect(res.delivered).toBe(1);
    expect(res.reason).toBe('wrong_destination');
    expect(res.failurePackage).toBe(1);
  });

  it('detects head-on deadlock', () => {
    const res = run('S1a I1 I1 S3b\nDa . . Db');
    expect(res.success).toBe(false);
    expect(res.reason).toBe('deadlock');
  });

  it('detects infinite loops', () => {
    // Tees route straight > right > left, trapping the package in a 2x2 cycle.
    const res = run(`
      S1a T1 T2 T3
      L3  T0 T3 T1
      I1  T0 L0 Da`);
    expect(res.success).toBe(false);
    expect(res.reason).toBe('loop');
  });

  it('crosses let two routes intersect', () => {
    const res = run(`
      .   S2b .
      S1a X   Da
      .   Db  .`);
    expect(res.success).toBe(true);
    expect(res.delivered).toBe(2);
  });

  it('is deterministic: identical inputs give identical frame streams', () => {
    const text = `
      S1a2 T1 S3b2
      .    X  .
      Db   L0 Da`;
    const a = run(text);
    const b = run(text);
    expect(JSON.stringify(a)).toEqual(JSON.stringify(b));
  });

  it('applies moves and rejects illegal ones', () => {
    const b = parseAscii('S1a L0 I0! Da');
    expect(applyMoves(b, [[1, 1], [1, 1], [1, -1]])).toEqual([1, 1, 0, 0]);
    expect(() => applyMoves(b, [[2, 1]])).toThrow(IllegalMoveError);
    expect(() => applyMoves(b, [[0, 1]])).toThrow(IllegalMoveError);
    expect(() => applyMoves(b, [[9, 1]])).toThrow(IllegalMoveError);
    expect(() => applyMoves(b, [[1, 2 as 1]])).toThrow(IllegalMoveError);
  });

  it('terminates within the tick bound for every rotation of a dense board', () => {
    const b = parseAscii(`
      S1a T0 L1 T2
      X   T1 L2 L0
      L3  T3 X  Da`);
    for (let k = 0; k < 256; k++) {
      const rot = b.tiles.map((t, i) => (t.t === 'source' || t.t === 'dest' ? t.r : (k >> (i % 8)) & 3));
      const res = simulate(b, rot, { recordFrames: false });
      expect(res.ticks).toBeLessThanOrEqual(4 * 12 + 50);
    }
  });
});
