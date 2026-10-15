import { DX, DY, bit, opposite, type Dir } from './directions';
import type { Board, Difficulty, Level } from './level';
import { Rng } from './rng';
import { exitDirection, isSolved } from './simulation';
import { solve } from './solver';
import { rotateMask } from './directions';
import { isRotatable, type Tile, type TileType } from './tiles';

export const GENERATOR_VERSION = 'gen-1';

export interface TierConfig {
  width: number;
  height: number;
  paths: number;
  packagesMin: number;
  packagesMax: number;
  /** Conveyor tiles per route (excluding source and destination). */
  pathMin: number;
  pathMax: number;
  decoyPct: number;
  blockedPct: number;
  teePct: number;
  allowCross: boolean;
  lockedPct: number;
  minRotations: number;
  maxRotations: number;
  solverBudget: number;
}

export const TIERS: Record<Difficulty, TierConfig> = {
  beginner: { width: 4, height: 4, paths: 1, packagesMin: 1, packagesMax: 1, pathMin: 3, pathMax: 5, decoyPct: 35, blockedPct: 10, teePct: 0, allowCross: false, lockedPct: 0, minRotations: 2, maxRotations: 5, solverBudget: 20_000 },
  easy: { width: 5, height: 5, paths: 1, packagesMin: 1, packagesMax: 2, pathMin: 5, pathMax: 9, decoyPct: 55, blockedPct: 10, teePct: 0, allowCross: false, lockedPct: 10, minRotations: 4, maxRotations: 9, solverBudget: 40_000 },
  medium: { width: 5, height: 6, paths: 2, packagesMin: 1, packagesMax: 2, pathMin: 3, pathMax: 7, decoyPct: 60, blockedPct: 8, teePct: 15, allowCross: false, lockedPct: 10, minRotations: 6, maxRotations: 14, solverBudget: 60_000 },
  hard: { width: 6, height: 6, paths: 2, packagesMin: 2, packagesMax: 2, pathMin: 5, pathMax: 9, decoyPct: 65, blockedPct: 8, teePct: 20, allowCross: true, lockedPct: 15, minRotations: 8, maxRotations: 18, solverBudget: 80_000 },
  expert: { width: 6, height: 7, paths: 3, packagesMin: 1, packagesMax: 3, pathMin: 4, pathMax: 9, decoyPct: 70, blockedPct: 6, teePct: 25, allowCross: true, lockedPct: 15, minRotations: 10, maxRotations: 24, solverBudget: 120_000 },
};

const MAX_ATTEMPTS = 60;

interface Cell {
  t: TileType;
  r: number;
  l: boolean;
  c: number;
  n: number;
  /** Route that owns this cell (-1 none). */
  owner: number;
}

/** Orientation of a corner connecting sides a and b. */
function cornerRotation(a: number, b: number): number {
  const mask = bit(a) | bit(b);
  for (let r = 0; r < 4; r++) if (rotateMask(0b0011, r) === mask) return r;
  return 0;
}

interface RouteStep {
  cell: number;
  /** Travel direction when entering the cell. */
  inDir: Dir;
  /** Travel direction when leaving the cell. */
  outDir: Dir;
}

function buildRoute(rng: Rng, grid: Cell[], w: number, h: number, cfg: TierConfig, owner: number): { source: number; srcDir: Dir; steps: RouteStep[]; dest: number } | null {
  const free = (i: number) => grid[i]!.t === 'empty' && grid[i]!.owner < 0;
  const freeCells: number[] = [];
  for (let i = 0; i < grid.length; i++) if (free(i)) freeCells.push(i);
  if (freeCells.length < cfg.pathMin + 2) return null;
  const source = rng.pick(freeCells);
  const target = rng.range(cfg.pathMin, cfg.pathMax);
  const sx = source % w;
  const sy = Math.floor(source / w);

  const dirs: Dir[] = rng.shuffle([0, 1, 2, 3] as Dir[]);
  let budget = 3000;
  const path: RouteStep[] = [];
  const inPath = new Set<number>([source]);

  // Can the route step from (x,y) in direction d? Returns the next cell or -1.
  const stepTo = (cell: number, d: Dir): number => {
    const x = (cell % w) + DX[d];
    const y = Math.floor(cell / w) + DY[d];
    if (x < 0 || y < 0 || x >= w || y >= h) return -1;
    return y * w + x;
  };
  const crossable = (cell: number, d: Dir): boolean => {
    if (!cfg.allowCross) return false;
    const c = grid[cell]!;
    if (c.owner < 0 || c.owner === owner || c.t !== 'straight' || c.l) return false;
    // existing straight must be perpendicular to our travel direction
    const vertical = c.r % 2 === 0;
    return vertical ? d % 2 === 1 : d % 2 === 0;
  };

  let destCell = -1;
  const dfs = (cell: number, dir: Dir): boolean => {
    if (--budget <= 0) return false;
    if (path.length >= target) {
      // try to finish into a destination cell
      for (const d of rng.shuffle([0, 1, 2, 3] as Dir[])) {
        if (d === opposite(dir)) continue;
        const n = stepTo(cell, d);
        if (n >= 0 && free(n) && !inPath.has(n)) {
          path[path.length - 1]!.outDir = d;
          destCell = n;
          return true;
        }
      }
      return false;
    }
    const last = path[path.length - 1]!;
    const forcedStraight = grid[cell]!.owner >= 0 && grid[cell]!.owner !== owner; // crossing cell
    const options = forcedStraight ? [dir] : rng.shuffle([0, 1, 2, 3] as Dir[]).filter((d) => d !== opposite(dir));
    for (const d of options) {
      const n = stepTo(cell, d);
      if (n < 0 || inPath.has(n)) continue;
      if (!free(n) && !crossable(n, d)) continue;
      last.outDir = d;
      path.push({ cell: n, inDir: d, outDir: d });
      inPath.add(n);
      if (dfs(n, d)) return true;
      path.pop();
      inPath.delete(n);
      if (budget <= 0) return false;
    }
    return false;
  };

  for (const d of dirs) {
    const nx = sx + DX[d];
    const ny = sy + DY[d];
    if (nx < 0 || ny < 0 || nx >= w || ny >= h) continue;
    const first = ny * w + nx;
    if (!free(first)) continue;
    path.length = 0;
    path.push({ cell: first, inDir: d, outDir: d });
    inPath.clear();
    inPath.add(source);
    inPath.add(first);
    if (dfs(first, d)) {
      // Crossing must not be the last conveyor before the destination turn (it is forced straight anyway).
      return { source, srcDir: d, steps: path.slice(), dest: destCell };
    }
    if (budget <= 0) break;
  }
  return null;
}

function tryGenerate(rng: Rng, cfg: TierConfig): { tiles: Tile[]; solvedRotations: number[] } | null {
  const w = cfg.width;
  const h = cfg.height;
  const grid: Cell[] = [];
  for (let i = 0; i < w * h; i++) grid.push({ t: 'empty', r: 0, l: false, c: 0, n: 1, owner: -1 });

  for (let k = 0; k < cfg.paths; k++) {
    const route = buildRoute(rng, grid, w, h, cfg, k);
    if (!route) return null;
    grid[route.source] = { t: 'source', r: route.srcDir, l: true, c: k, n: rng.range(cfg.packagesMin, cfg.packagesMax), owner: k };
    grid[route.dest] = { t: 'dest', r: 0, l: true, c: k, n: 1, owner: k };
    for (const step of route.steps) {
      const existing = grid[step.cell]!;
      if (existing.owner >= 0 && existing.owner !== k) {
        grid[step.cell] = { t: 'cross', r: 0, l: false, c: 0, n: 1, owner: k };
        continue;
      }
      if (step.inDir === step.outDir) {
        grid[step.cell] = { t: 'straight', r: step.inDir % 2 === 0 ? 0 : 1, l: false, c: 0, n: 1, owner: k };
      } else {
        grid[step.cell] = { t: 'corner', r: cornerRotation(opposite(step.inDir), step.outDir), l: false, c: 0, n: 1, owner: k };
      }
      // Optionally replace with a tee that routes identically.
      if (cfg.teePct > 0 && rng.chance(cfg.teePct)) {
        const tee: Tile = { t: 'tee', r: 0 };
        const opts: number[] = [];
        for (let r = 0; r < 4; r++) {
          if (!(rotateMask(0b0111, r) & bit(opposite(step.inDir)))) continue;
          if (exitDirection(tee, r, step.inDir) === step.outDir) opts.push(r);
        }
        if (opts.length > 0) grid[step.cell] = { t: 'tee', r: rng.pick(opts), l: false, c: 0, n: 1, owner: k };
      }
    }
  }

  // Decoys and obstacles on unused cells.
  const decoyTypes: TileType[] = cfg.teePct > 0 ? ['straight', 'corner', 'corner', 'tee'] : ['straight', 'corner', 'corner'];
  for (let i = 0; i < grid.length; i++) {
    const c = grid[i]!;
    if (c.owner >= 0) continue;
    if (rng.chance(cfg.blockedPct)) {
      grid[i] = { t: 'blocked', r: 0, l: false, c: 0, n: 1, owner: -1 };
    } else if (rng.chance(cfg.decoyPct)) {
      grid[i] = { t: rng.pick(decoyTypes), r: rng.int(4), l: false, c: 0, n: 1, owner: -1 };
    }
  }

  // Locked anchors along routes.
  if (cfg.lockedPct > 0) {
    for (let i = 0; i < grid.length; i++) {
      const c = grid[i]!;
      if (c.owner >= 0 && (c.t === 'straight' || c.t === 'corner' || c.t === 'tee') && rng.chance(cfg.lockedPct)) c.l = true;
    }
  }

  const solvedRotations = grid.map((c) => c.r);
  const tiles: Tile[] = grid.map((c) => {
    const t: Tile = { t: c.t, r: c.r };
    if (c.l && (c.t === 'straight' || c.t === 'corner' || c.t === 'tee')) t.l = true;
    if (c.t === 'source' || c.t === 'dest') t.c = c.c;
    if (c.t === 'source' && c.n !== 1) t.n = c.n;
    return t;
  });

  // Scramble every rotatable tile.
  for (const t of tiles) if (isRotatable(t)) t.r = rng.int(4);
  return { tiles, solvedRotations };
}

export function difficultyScore(tiles: Tile[], par: number, paths: number): number {
  let rotatable = 0;
  let crosses = 0;
  let tees = 0;
  let packages = 0;
  for (const t of tiles) {
    if (isRotatable(t)) rotatable++;
    if (t.t === 'cross') crosses++;
    if (t.t === 'tee') tees++;
    if (t.t === 'source') packages += t.n ?? 1;
  }
  return par * 10 + rotatable * 3 + paths * 15 + packages * 4 + crosses * 5 + tees * 4;
}

export interface GenerateOptions {
  id?: string;
  name?: string;
}

/**
 * Generate a verified puzzle for a tier from a seed. Fully deterministic for (seed, tier, GENERATOR_VERSION).
 * Returns null if no acceptable puzzle was found within MAX_ATTEMPTS (callers try the next seed).
 */
export function generateLevel(seed: number, tier: Difficulty, options: GenerateOptions = {}): Level | null {
  const cfg = TIERS[tier];
  const rng = new Rng(seed);
  for (let attempt = 0; attempt < MAX_ATTEMPTS; attempt++) {
    const built = tryGenerate(rng, cfg);
    if (!built) continue;
    const board: Board = { width: cfg.width, height: cfg.height, tiles: built.tiles };
    const start = built.tiles.map((t) => t.r);
    // The intended configuration must actually work (validates routes), and the start must not.
    if (!isSolved(board, built.solvedRotations)) continue;
    if (isSolved(board, start)) continue;
    const res = solve(board, start, { maxNodes: cfg.solverBudget, countCap: 20 });
    if (res.status !== 'solved' || !res.rotations) continue;
    if (res.minCost < cfg.minRotations || res.minCost > cfg.maxRotations) continue;
    return {
      id: options.id ?? `${tier}-${seed >>> 0}`,
      name: options.name ?? `${tier[0]!.toUpperCase()}${tier.slice(1)} #${seed >>> 0}`,
      version: 1,
      difficulty: tier,
      difficultyScore: difficultyScore(built.tiles, res.minCost, cfg.paths),
      width: cfg.width,
      height: cfg.height,
      tiles: built.tiles,
      generator: { version: GENERATOR_VERSION, seed: seed >>> 0, tier },
      par: res.minCost,
      solution: { rotations: res.rotations, moves: res.moves },
      solutionCount: res.solutionCount,
      solutionCountCapped: res.solutionCountCapped,
    };
  }
  return null;
}

/** Generate with automatic seed advancement: tries seed, seed+1, ... until a level is produced. */
export function generateLevelFrom(seed: number, tier: Difficulty, options: GenerateOptions = {}, maxSeeds = 50): Level | null {
  for (let k = 0; k < maxSeeds; k++) {
    const lvl = generateLevel((seed + k) >>> 0, tier, options);
    if (lvl) return lvl;
  }
  return null;
}
