import { DX, DY, bit, opposite, turnLeft, turnRight, type Dir } from './directions';
import type { Board } from './level';
import { inputMask, outputMask, type Tile } from './tiles';

/**
 * Deterministic tick-based conveyor simulation.
 *
 * Rules (also documented in docs/gameplay-rules.md):
 *  - Tick 0: every source with packages left spawns one package on its own cell, facing its orientation.
 *  - Each later tick:
 *    1. Intent: every package tries to step one cell in its travel direction. It crashes if it would
 *       leave the board or enter a cell whose input mask lacks the entry side. Entering a destination
 *       of a different color is a "wrong_destination" failure. Otherwise the new travel direction is
 *       chosen by the target tile: straight if possible, else turn right, else turn left.
 *    2. Any crash ends the simulation (failure), reported for the lowest package id.
 *    3. Conflict resolution (fixed point, deterministic):
 *       - Packages entering a destination never conflict (destinations have unlimited capacity).
 *       - Several packages targeting the same cell: lowest package id wins, others wait.
 *       - Two packages targeting each other's cells (head-on): both wait.
 *       - A package targeting a cell whose occupant waits must also wait.
 *    4. Accepted moves apply simultaneously; packages entering their destination are delivered.
 *    5. Sources spawn into their cell if it is free (sources processed in tile index order).
 *    6. Evaluate: all packages delivered → success; nothing moved/spawned → deadlock;
 *       a repeated global state → loop; tick limit reached → timeout.
 *  Rendering frame rate never affects results: the renderer only interpolates between frames.
 */

export type FailureReason = 'off_board' | 'disconnected' | 'wrong_destination' | 'deadlock' | 'loop' | 'timeout';

export interface PackageState {
  id: number;
  color: number;
  /** Cell index (row-major). */
  cell: number;
  /** Current travel direction (the side it will exit through). */
  dir: Dir;
  /** Source cell it came from. */
  source: number;
}

export interface FramePackage {
  id: number;
  color: number;
  cell: number;
  dir: Dir;
  /** 'spawned' on its first frame, 'moved'/'waiting' afterwards, 'delivered' on the frame it arrives. */
  state: 'spawned' | 'moved' | 'waiting' | 'delivered' | 'crashed';
  /** For crashed packages: the cell (or off-board position) it tried to enter. */
  toX?: number;
  toY?: number;
}

export interface Frame {
  tick: number;
  packages: FramePackage[];
  delivered: number;
}

export interface SimulationResult {
  success: boolean;
  reason: FailureReason | null;
  ticks: number;
  delivered: number;
  total: number;
  /** Package and cell involved in the failure, if any. */
  failurePackage: number | null;
  failureCell: number | null;
  frames: Frame[];
}

export interface SimulateOptions {
  /** Record per-tick frames for rendering (default true). */
  recordFrames?: boolean;
  maxTicks?: number;
}

interface Intent {
  pkg: PackageState;
  target: number;
  newDir: Dir;
  deliver: boolean;
}

/** Exit direction for a package entering `tile` while travelling in `dir`, or -1 for a dead end. */
export function exitDirection(tile: Tile, r: number, dir: Dir): number {
  const out = outputMask(tile, r) & ~bit(opposite(dir));
  if (out & bit(dir)) return dir;
  const right = turnRight(dir);
  if (out & bit(right)) return right;
  const left = turnLeft(dir);
  if (out & bit(left)) return left;
  return -1;
}

export function totalPackages(board: Board): number {
  let total = 0;
  for (const t of board.tiles) if (t.t === 'source') total += t.n ?? 1;
  return total;
}

export function simulate(board: Board, rotations: readonly number[], options: SimulateOptions = {}): SimulationResult {
  const { width, height, tiles } = board;
  const record = options.recordFrames ?? true;
  const total = totalPackages(board);
  const maxTicks = options.maxTicks ?? 4 * width * height * Math.max(1, total) + 50;

  const remaining = tiles.map((t) => (t.t === 'source' ? (t.n ?? 1) : 0));
  let packages: PackageState[] = [];
  let nextId = 0;
  let delivered = 0;
  const frames: Frame[] = [];
  const seen = new Set<string>();

  const occupied = (cell: number) => packages.some((p) => p.cell === cell);

  const spawn = (states: Map<number, FramePackage['state']>): boolean => {
    let spawned = false;
    for (let i = 0; i < tiles.length; i++) {
      const t = tiles[i] as Tile;
      if (t.t !== 'source' || (remaining[i] as number) <= 0 || occupied(i)) continue;
      const pkg: PackageState = { id: nextId++, color: t.c ?? 0, cell: i, dir: ((rotations[i] as number) & 3) as Dir, source: i };
      packages.push(pkg);
      remaining[i] = (remaining[i] as number) - 1;
      states.set(pkg.id, 'spawned');
      spawned = true;
    }
    return spawned;
  };

  const snapshot = (tick: number, states: Map<number, FramePackage['state']>, extra: FramePackage[] = []) => {
    if (!record) return;
    const list: FramePackage[] = packages.map((p) => ({ id: p.id, color: p.color, cell: p.cell, dir: p.dir, state: states.get(p.id) ?? 'moved' }));
    list.push(...extra);
    list.sort((a, b) => a.id - b.id);
    frames.push({ tick, packages: list, delivered });
  };

  const finish = (success: boolean, reason: FailureReason | null, tick: number, pkg: number | null = null, cell: number | null = null): SimulationResult => ({
    success,
    reason,
    ticks: tick,
    delivered,
    total,
    failurePackage: pkg,
    failureCell: cell,
    frames,
  });

  // Tick 0: initial spawn.
  {
    const states = new Map<number, FramePackage['state']>();
    spawn(states);
    snapshot(0, states);
  }

  for (let tick = 1; tick <= maxTicks; tick++) {
    // 1. Intents.
    const intents: Intent[] = [];
    for (const pkg of packages) {
      const x = pkg.cell % width;
      const y = Math.floor(pkg.cell / width);
      const nx = x + DX[pkg.dir];
      const ny = y + DY[pkg.dir];
      const crash = (reason: FailureReason, cell: number | null) => {
        const states = new Map<number, FramePackage['state']>();
        for (const p of packages) states.set(p.id, 'waiting');
        packages = packages.filter((p) => p.id !== pkg.id);
        snapshot(tick, states, [{ id: pkg.id, color: pkg.color, cell: pkg.cell, dir: pkg.dir, state: 'crashed', toX: nx, toY: ny }]);
        return finish(false, reason, tick, pkg.id, cell);
      };
      if (nx < 0 || ny < 0 || nx >= width || ny >= height) return crash('off_board', null);
      const target = ny * width + nx;
      const tile = tiles[target] as Tile;
      const r = rotations[target] as number;
      if (!(inputMask(tile, r) & bit(opposite(pkg.dir)))) return crash('disconnected', target);
      if (tile.t === 'dest') {
        if ((tile.c ?? 0) !== pkg.color) return crash('wrong_destination', target);
        intents.push({ pkg, target, newDir: pkg.dir, deliver: true });
        continue;
      }
      const ex = exitDirection(tile, r, pkg.dir);
      if (ex < 0) return crash('disconnected', target);
      intents.push({ pkg, target, newDir: ex as Dir, deliver: false });
    }

    // 3. Conflict resolution to a fixed point.
    const accepted = new Map<number, Intent>();
    for (const it of intents) accepted.set(it.pkg.id, it);
    const byCell = new Map<number, PackageState>();
    for (const p of packages) byCell.set(p.cell, p);
    let changed = true;
    while (changed) {
      changed = false;
      const claims = new Map<number, number>(); // target cell -> lowest accepted package id
      for (const it of accepted.values()) {
        if (it.deliver) continue;
        const prev = claims.get(it.target);
        if (prev === undefined || it.pkg.id < prev) claims.set(it.target, it.pkg.id);
      }
      for (const it of [...accepted.values()]) {
        if (it.deliver) continue;
        if (claims.get(it.target) !== it.pkg.id) {
          accepted.delete(it.pkg.id);
          changed = true;
          continue;
        }
        const occupant = byCell.get(it.target);
        if (occupant && occupant.id !== it.pkg.id) {
          const occIntent = accepted.get(occupant.id);
          if (!occIntent) {
            accepted.delete(it.pkg.id);
            changed = true;
          } else if (!occIntent.deliver && occIntent.target === it.pkg.cell) {
            accepted.delete(it.pkg.id);
            accepted.delete(occupant.id);
            changed = true;
          }
        }
      }
    }

    // 4. Apply.
    const states = new Map<number, FramePackage['state']>();
    const deliveredNow: FramePackage[] = [];
    const survivors: PackageState[] = [];
    for (const p of packages) {
      const it = accepted.get(p.id);
      if (!it) {
        states.set(p.id, 'waiting');
        survivors.push(p);
      } else if (it.deliver) {
        delivered++;
        deliveredNow.push({ id: p.id, color: p.color, cell: it.target, dir: p.dir, state: 'delivered' });
      } else {
        p.cell = it.target;
        p.dir = it.newDir;
        states.set(p.id, 'moved');
        survivors.push(p);
      }
    }
    packages = survivors;
    const moved = accepted.size > 0;

    // 5. Spawn.
    const spawned = spawn(states);
    snapshot(tick, states, deliveredNow);

    // 6. Evaluate.
    if (delivered === total) return finish(true, null, tick);
    if (!moved && !spawned) {
      const stuck = packages[0];
      return finish(false, 'deadlock', tick, stuck?.id ?? null, stuck?.cell ?? null);
    }
    const key = packages.map((p) => `${p.id}:${p.cell}:${p.dir}`).join('|') + '#' + remaining.join(',');
    if (seen.has(key)) {
      const looping = packages[0];
      return finish(false, 'loop', tick, looping?.id ?? null, looping?.cell ?? null);
    }
    seen.add(key);
  }
  return finish(false, 'timeout', maxTicks);
}

/** Convenience: does this configuration solve the board? */
export function isSolved(board: Board, rotations: readonly number[]): boolean {
  return simulate(board, rotations, { recordFrames: false }).success;
}
