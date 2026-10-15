import { bit, rotateMask } from './directions';

export const TILE_TYPES = ['empty', 'blocked', 'straight', 'corner', 'tee', 'cross', 'source', 'dest'] as const;
export type TileType = (typeof TILE_TYPES)[number];

/** Number of package colors supported by the palette (colorblind-safe symbols exist for each). */
export const COLOR_COUNT = 4;

export interface Tile {
  /** Tile type. */
  t: TileType;
  /** Orientation: clockwise quarter turns from the base orientation (0..3). */
  r: number;
  /** Locked: cannot be rotated by the player even if the type normally can. */
  l?: boolean;
  /** Color index for sources and destinations (0..COLOR_COUNT-1). */
  c?: number;
  /** Number of packages a source emits (default 1). */
  n?: number;
}

/** Base connection masks at r = 0. N=1, E=2, S=4, W=8. */
const BASE_MASK: Record<TileType, number> = {
  empty: 0,
  blocked: 0,
  straight: 0b0101, // N|S
  corner: 0b0011, // N|E
  tee: 0b0111, // N|E|S (closed on W)
  cross: 0b1111,
  source: 0, // sources emit along their orientation; they accept nothing
  dest: 0b1111, // destinations accept packages from any side
};

/** Rotational period of each tile type: rotations r and r+period look and behave identically. */
export const PERIOD: Record<TileType, number> = {
  empty: 1,
  blocked: 1,
  straight: 2,
  corner: 4,
  tee: 4,
  cross: 1,
  source: 4,
  dest: 1,
};

export function isConveyor(t: TileType): boolean {
  return t === 'straight' || t === 'corner' || t === 'tee' || t === 'cross';
}

/** Whether the player may rotate this tile. Crosses are symmetric, so rotating them is a no-op and disallowed. */
export function isRotatable(tile: Tile): boolean {
  if (tile.l) return false;
  return tile.t === 'straight' || tile.t === 'corner' || tile.t === 'tee';
}

/** Sides through which a package may enter this tile at orientation r. */
export function inputMask(tile: Tile, r: number = tile.r): number {
  if (tile.t === 'source') return 0;
  return rotateMask(BASE_MASK[tile.t], r);
}

/** Sides through which a package may leave this tile at orientation r. */
export function outputMask(tile: Tile, r: number = tile.r): number {
  if (tile.t === 'source') return bit(r & 3);
  if (tile.t === 'dest') return 0;
  return rotateMask(BASE_MASK[tile.t], r);
}

/** Undirected visual connection mask (for rendering). */
export function connectionMask(tile: Tile, r: number = tile.r): number {
  return inputMask(tile, r) | outputMask(tile, r);
}

/** Canonical orientation in [0, period). */
export function canonicalRotation(tile: Tile, r: number): number {
  return (((r % 4) + 4) % 4) % PERIOD[tile.t];
}

/**
 * Minimum number of single quarter-turn actions (clockwise or counter-clockwise) needed to bring
 * the tile from orientation `from` to an orientation equivalent to `to`.
 */
export function rotationCost(tile: Tile, from: number, to: number): number {
  const p = PERIOD[tile.t];
  let best = 4;
  for (let k = 0; k < 4; k += p) {
    const target = (to + k) & 3;
    const cw = (((target - from) % 4) + 4) % 4;
    const ccw = (4 - cw) % 4;
    best = Math.min(best, cw, ccw);
  }
  return best;
}
