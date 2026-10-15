import { COLOR_COUNT, TILE_TYPES, isRotatable, type Tile } from './tiles';

export const DIFFICULTIES = ['beginner', 'easy', 'medium', 'hard', 'expert'] as const;
export type Difficulty = (typeof DIFFICULTIES)[number];

/** A single player action: rotate tile `index` clockwise (dir = 1) or counter-clockwise (dir = -1). */
export type Move = [index: number, dir: 1 | -1];

export interface LevelSolution {
  /** Final orientation for every tile (row-major), as found by the solver. */
  rotations: number[];
  /** A minimal move sequence from the starting board to `rotations`. */
  moves: Move[];
}

export interface GeneratorInfo {
  version: string;
  seed: number;
  tier: Difficulty;
}

export interface Level {
  id: string;
  name: string;
  /** Content version: bump whenever the board changes so stale replays are rejected. */
  version: number;
  difficulty: Difficulty;
  difficultyScore: number;
  width: number;
  height: number;
  /** Row-major tiles in their *starting* (scrambled) orientation. Tile ID = index. */
  tiles: Tile[];
  generator: GeneratorInfo | null;
  /** Minimum rotations needed (verified by the solver). */
  par: number;
  solution: LevelSolution;
  /** Number of distinct solved configurations found, capped at solutionCountCap. */
  solutionCount: number;
  solutionCountCapped: boolean;
  /** Optional tutorial hint text shown above the board. */
  tip?: string;
}

/** The minimal board description the simulation needs. */
export interface Board {
  width: number;
  height: number;
  tiles: Tile[];
}

export class LevelValidationError extends Error {}

/** Structural validation for untrusted board data (levels from disk, network or saves). */
export function validateBoard(board: Board): void {
  const { width, height, tiles } = board;
  if (!Number.isInteger(width) || !Number.isInteger(height) || width < 2 || height < 2 || width > 12 || height > 12) {
    throw new LevelValidationError('Board dimensions must be integers between 2 and 12');
  }
  if (!Array.isArray(tiles) || tiles.length !== width * height) {
    throw new LevelValidationError('Tile count must equal width * height');
  }
  let sources = 0;
  let dests = 0;
  const sourceColors = new Map<number, number>();
  const destColors = new Set<number>();
  tiles.forEach((tile, i) => {
    if (!tile || !(TILE_TYPES as readonly string[]).includes(tile.t)) throw new LevelValidationError(`Tile ${i}: unknown type`);
    if (!Number.isInteger(tile.r) || tile.r < 0 || tile.r > 3) throw new LevelValidationError(`Tile ${i}: rotation must be 0..3`);
    if (tile.t === 'source' || tile.t === 'dest') {
      const c = tile.c ?? 0;
      if (!Number.isInteger(c) || c < 0 || c >= COLOR_COUNT) throw new LevelValidationError(`Tile ${i}: invalid color`);
    }
    if (tile.t === 'source') {
      const n = tile.n ?? 1;
      if (!Number.isInteger(n) || n < 1 || n > 9) throw new LevelValidationError(`Tile ${i}: source count must be 1..9`);
      sources++;
      sourceColors.set(tile.c ?? 0, (sourceColors.get(tile.c ?? 0) ?? 0) + n);
    }
    if (tile.t === 'dest') {
      dests++;
      destColors.add(tile.c ?? 0);
    }
  });
  if (sources === 0) throw new LevelValidationError('Board needs at least one source');
  if (dests === 0) throw new LevelValidationError('Board needs at least one destination');
  for (const color of sourceColors.keys()) {
    if (!destColors.has(color)) throw new LevelValidationError(`No destination for color ${color}`);
  }
}

export function rotatableIndices(board: Board): number[] {
  const out: number[] = [];
  board.tiles.forEach((t, i) => {
    if (isRotatable(t)) out.push(i);
  });
  return out;
}

export function startRotations(board: Board): number[] {
  return board.tiles.map((t) => t.r);
}

export class IllegalMoveError extends Error {}

/**
 * Apply a move sequence to a board's starting rotations. Throws IllegalMoveError for moves on
 * out-of-range or non-rotatable tiles. Used by the client (undo/replay) and server (score validation).
 */
export function applyMoves(board: Board, moves: readonly Move[], from: readonly number[] = startRotations(board)): number[] {
  const rot = from.slice();
  for (const mv of moves) {
    if (!Array.isArray(mv) || mv.length !== 2) throw new IllegalMoveError('Malformed move');
    const [index, dir] = mv;
    if (!Number.isInteger(index) || index < 0 || index >= board.tiles.length) throw new IllegalMoveError(`Tile ${index} out of range`);
    if (dir !== 1 && dir !== -1) throw new IllegalMoveError('Move direction must be 1 or -1');
    const tile = board.tiles[index] as (typeof board.tiles)[number];
    if (!isRotatable(tile)) throw new IllegalMoveError(`Tile ${index} cannot be rotated`);
    rot[index] = ((rot[index] as number) + dir + 4) & 3;
  }
  return rot;
}
