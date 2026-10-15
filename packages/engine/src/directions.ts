/**
 * Cardinal directions. Numeric values are part of the save/replay format — never reorder.
 * Bit masks use bit(d) = 1 << d, so N=1, E=2, S=4, W=8.
 */
export const NORTH = 0;
export const EAST = 1;
export const SOUTH = 2;
export const WEST = 3;
export type Dir = 0 | 1 | 2 | 3;

export const DIR_NAMES = ['NORTH', 'EAST', 'SOUTH', 'WEST'] as const;
export const DX = [0, 1, 0, -1] as const;
export const DY = [-1, 0, 1, 0] as const;

export const bit = (d: number): number => 1 << d;
export const opposite = (d: number): Dir => ((d + 2) & 3) as Dir;
export const turnRight = (d: number): Dir => ((d + 1) & 3) as Dir;
export const turnLeft = (d: number): Dir => ((d + 3) & 3) as Dir;

/** Rotate a 4-bit connection mask clockwise `times` quarter turns. */
export function rotateMask(mask: number, times: number): number {
  let m = mask & 15;
  const t = ((times % 4) + 4) % 4;
  for (let i = 0; i < t; i++) m = ((m << 1) | (m >> 3)) & 15;
  return m;
}
