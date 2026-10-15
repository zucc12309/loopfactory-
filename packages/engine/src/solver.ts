import { DX, DY, bit, opposite, type Dir } from './directions';
import type { Board, Move } from './level';
import { exitDirection, simulate } from './simulation';
import { PERIOD, inputMask, isRotatable, rotationCost, type Tile } from './tiles';

/**
 * Bounded path-constrained backtracking solver.
 *
 * Package routes depend only on the orientations of tiles they traverse, so instead of enumerating
 * every orientation of every tile (exponential in board size) the solver traces each source's route
 * and branches only on rotatable tiles the route actually enters, and only on orientations that
 * accept the package from its entry side. Tiles never visited keep their current orientation (cost 0).
 * Every complete candidate is verified with the full multi-package simulation (catching deadlocks,
 * timing conflicts and loops), so the solver never accepts a configuration the game would reject.
 *
 * Branch-and-bound on accumulated rotation cost gives the exact minimum number of rotations
 * (rotationCost counts clockwise and counter-clockwise quarter turns as one action each).
 */

export type SolveStatus = 'solved' | 'unsolvable' | 'budget_exceeded';

export interface SolveOptions {
  /** Maximum search nodes before giving up (default 200 000). */
  maxNodes?: number;
  /** Also count distinct solved configurations up to this cap (0 = skip counting). */
  countCap?: number;
}

export interface SolveResult {
  status: SolveStatus;
  /** Minimum rotations from the given start rotations (only when solved). */
  minCost: number;
  rotations: number[] | null;
  moves: Move[];
  /** Tiles in the order the optimal routes traverse them (used for hints). */
  routeOrder: number[];
  nodes: number;
  solutionCount: number;
  solutionCountCapped: boolean;
}

interface SearchState {
  board: Board;
  start: readonly number[];
  rot: number[];
  assigned: boolean[];
  sources: number[];
  nodes: number;
  maxNodes: number;
  exceeded: boolean;
  bestCost: number;
  best: number[] | null;
  bestOrder: number[];
  order: number[];
  countMode: boolean;
  countCap: number;
  count: number;
  seenSolutions: Set<string>;
}

function orientationsFor(tile: Tile, start: number): number[] {
  // Distinct orientations, cheapest first (ties broken by orientation value) for deterministic search.
  const p = PERIOD[tile.t];
  const opts: number[] = [];
  for (let k = 0; k < p; k++) opts.push((start + k) & 3);
  return opts
    .map((r) => ({ r, c: rotationCost(tile, start, r) }))
    .sort((a, b) => a.c - b.c || a.r - b.r)
    .map((o) => o.r);
}

function costOf(s: SearchState): number {
  let c = 0;
  for (let i = 0; i < s.rot.length; i++) {
    if (s.assigned[i]) c += rotationCost(s.board.tiles[i] as Tile, s.start[i] as number, s.rot[i] as number);
  }
  return c;
}

function onCandidate(s: SearchState): void {
  const sim = simulate(s.board, s.rot, { recordFrames: false });
  if (!sim.success) return;
  if (s.countMode) {
    const key = s.rot.map((r, i) => (r % PERIOD[(s.board.tiles[i] as Tile).t])).join('');
    if (!s.seenSolutions.has(key)) {
      s.seenSolutions.add(key);
      s.count++;
    }
    return;
  }
  const cost = costOf(s);
  if (cost < s.bestCost) {
    s.bestCost = cost;
    s.best = s.rot.slice();
    s.bestOrder = s.order.slice();
  }
}

function done(s: SearchState): boolean {
  if (s.exceeded) return true;
  if (s.countMode) return s.count >= s.countCap;
  return s.bestCost === 0;
}

function solveSource(s: SearchState, si: number): void {
  if (done(s)) return;
  if (si >= s.sources.length) {
    onCandidate(s);
    return;
  }
  const src = s.sources[si] as number;
  trace(s, si, src, ((s.rot[src] as number) & 3) as Dir, new Set<number>());
}

function trace(s: SearchState, si: number, cell: number, dir: Dir, visited: Set<number>): void {
  if (done(s)) return;
  if (++s.nodes > s.maxNodes) {
    s.exceeded = true;
    return;
  }
  if (!s.countMode && costOf(s) >= s.bestCost) return;
  const { width, height, tiles } = s.board;
  const x = (cell % width) + DX[dir];
  const y = Math.floor(cell / width) + DY[dir];
  if (x < 0 || y < 0 || x >= width || y >= height) return;
  const next = y * width + x;
  const tile = tiles[next] as Tile;
  const entry = opposite(dir);

  const follow = () => {
    const r = s.rot[next] as number;
    if (!(inputMask(tile, r) & bit(entry))) return;
    if (tile.t === 'dest') {
      const srcTile = tiles[s.sources[si] as number] as Tile;
      if ((tile.c ?? 0) === (srcTile.c ?? 0)) solveSource(s, si + 1);
      return;
    }
    const ex = exitDirection(tile, r, dir);
    if (ex < 0) return;
    const key = next * 4 + ex;
    if (visited.has(key)) return; // route loops forever
    visited.add(key);
    s.order.push(next);
    trace(s, si, next, ex as Dir, visited);
    s.order.pop();
    visited.delete(key);
  };

  if (isRotatable(tile) && !s.assigned[next]) {
    const start = s.start[next] as number;
    s.assigned[next] = true;
    for (const r of orientationsFor(tile, start)) {
      if (!(inputMask(tile, r) & bit(entry))) continue;
      s.rot[next] = r;
      follow();
      if (done(s)) break;
    }
    s.rot[next] = start;
    s.assigned[next] = false;
  } else {
    follow();
  }
}

/** Cheapest way to rotate a tile from `from` to an orientation equivalent to `to`: [taps, direction]. */
export function rotationPlan(tile: Tile, from: number, to: number): [number, 1 | -1] {
  const cost = rotationCost(tile, from, to);
  for (let k = 0; k < 4; k += PERIOD[tile.t]) {
    if ((((to + k - from) % 4) + 4) % 4 === cost) return [cost, 1];
  }
  return [cost, -1];
}

/** Minimal move list turning `from` into `to` (counter-clockwise when cheaper), in tile order. */
export function movesBetween(board: Board, from: readonly number[], to: readonly number[]): Move[] {
  const moves: Move[] = [];
  board.tiles.forEach((tile, i) => {
    if (!isRotatable(tile)) return;
    const [cost, dir] = rotationPlan(tile, from[i] as number, to[i] as number);
    for (let n = 0; n < cost; n++) moves.push([i, dir]);
  });
  return moves;
}

function newState(board: Board, start: readonly number[], options: SolveOptions, countMode: boolean): SearchState {
  const sources: number[] = [];
  board.tiles.forEach((t, i) => {
    if (t.t === 'source') sources.push(i);
  });
  return {
    board,
    start,
    rot: start.slice(),
    assigned: board.tiles.map(() => false),
    sources,
    nodes: 0,
    maxNodes: options.maxNodes ?? 200_000,
    exceeded: false,
    bestCost: Number.POSITIVE_INFINITY,
    best: null,
    bestOrder: [],
    order: [],
    countMode,
    countCap: options.countCap ?? 0,
    count: 0,
    seenSolutions: new Set(),
  };
}

export function solve(board: Board, start: readonly number[] = board.tiles.map((t) => t.r), options: SolveOptions = {}): SolveResult {
  const s = newState(board, start, options, false);
  solveSource(s, 0);
  let solutionCount = 0;
  let capped = false;
  let nodes = s.nodes;
  if (s.best && (options.countCap ?? 0) > 0) {
    const c = newState(board, start, options, true);
    solveSource(c, 0);
    solutionCount = c.count;
    capped = c.count >= c.countCap || c.exceeded;
    nodes += c.nodes;
  }
  if (s.best) {
    return {
      status: 'solved',
      minCost: s.bestCost,
      rotations: s.best,
      moves: movesBetween(board, start, s.best),
      routeOrder: s.bestOrder,
      nodes,
      solutionCount,
      solutionCountCapped: capped,
    };
  }
  return {
    status: s.exceeded ? 'budget_exceeded' : 'unsolvable',
    minCost: -1,
    rotations: null,
    moves: [],
    routeOrder: [],
    nodes,
    solutionCount: 0,
    solutionCountCapped: false,
  };
}

export interface Hint {
  tile: number;
  dir: 1 | -1;
  /** Taps still needed on this tile. */
  taps: number;
  targetRotation: number;
}

/**
 * Hint: the first tile along an optimal route (from the player's current rotations) that is not yet
 * in its solved orientation. Returns null when already solved or when the search budget is exhausted.
 */
export function hint(board: Board, current: readonly number[], options: SolveOptions = {}): Hint | null {
  const res = solve(board, current, { maxNodes: options.maxNodes ?? 100_000 });
  if (res.status !== 'solved' || !res.rotations || res.minCost === 0) return null;
  const target = res.rotations;
  const order = [...res.routeOrder, ...board.tiles.map((_, i) => i)];
  for (const i of order) {
    const tile = board.tiles[i] as Tile;
    if (!isRotatable(tile)) continue;
    const [taps, dir] = rotationPlan(tile, current[i] as number, target[i] as number);
    if (taps === 0) continue;
    return { tile: i, dir, taps, targetRotation: target[i] as number };
  }
  return null;
}
