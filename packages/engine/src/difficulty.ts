/**
 * Human-difficulty model. Minimum rotations alone is a poor predictor (a par-8 puzzle with one
 * obvious route is easier than a par-6 puzzle where two routes fight over a junction), so the
 * estimate combines six measurable signals:
 *
 *  - par            minimum rotations (solver-verified)
 *  - searchBits     log2 of the configuration space the player can reach (Π period of rotatable tiles)
 *  - routes         number of sources (independent routes to plan)
 *  - interactions   cells used by more than one route in the solution, plus ticks in which a
 *                   package had to wait (queueing at junctions/crossings)
 *  - mechanics      distinct mechanics present (corner, junction, crossing, pin, convoy, colours>1)
 *  - solverBits     log2 of solver search nodes — a proxy for how much backtracking is needed
 *
 * Weights were fitted by hand against the curated campaign's intended order and are documented in
 * docs/difficulty.md. They are a hypothesis to be re-fitted from analytics (time-to-solve, retries).
 */
import type { Level } from './level';
import { simulate } from './simulation';
import { solve } from './solver';
import { PERIOD, isRotatable } from './tiles';

export interface DifficultyMetrics {
  par: number;
  searchBits: number;
  routes: number;
  packages: number;
  interactions: number;
  waits: number;
  mechanics: string[];
  solverBits: number;
  cells: number;
  estimate: number;
}

export const DIFFICULTY_WEIGHTS = {
  par: 1.0,
  searchBits: 0.25,
  routes: 2.5,
  interactions: 1.2,
  mechanics: 0.8,
  solverBits: 0.6,
} as const;

export function mechanicsOf(level: Pick<Level, 'tiles'>): string[] {
  const m = new Set<string>();
  const colours = new Set<number>();
  for (const t of level.tiles) {
    if (t.t === 'corner') m.add('corner');
    if (t.t === 'tee') m.add('junction');
    if (t.t === 'cross') m.add('crossing');
    if ((t.t === 'straight' || t.t === 'corner' || t.t === 'tee' || t.t === 'cross') && t.l) m.add('pin');
    if (t.t === 'source') {
      colours.add(t.c ?? 0);
      if ((t.n ?? 1) > 1) m.add('convoy');
    }
  }
  if (colours.size > 1) m.add(`colours:${colours.size}`);
  return [...m].sort();
}

export function difficultyMetrics(level: Level): DifficultyMetrics {
  let searchBits = 0;
  for (const t of level.tiles) if (isRotatable(t)) searchBits += Math.log2(PERIOD[t.t]);
  const sources = level.tiles.filter((t) => t.t === 'source');
  const routes = sources.length;
  const packages = sources.reduce((n, t) => n + (t.n ?? 1), 0);
  const sim = simulate(level, level.solution.rotations);
  // Cells visited by packages from more than one source colour/route, and waiting ticks.
  const visitors = new Map<number, Set<number>>();
  let waits = 0;
  for (const f of sim.frames) {
    for (const p of f.packages) {
      if (p.state === 'waiting') waits++;
      let set = visitors.get(p.cell);
      if (!set) visitors.set(p.cell, (set = new Set()));
      set.add(p.color);
    }
  }
  let shared = 0;
  for (const s of visitors.values()) if (s.size > 1) shared++;
  const interactions = shared + Math.min(waits, 6) / 2;
  const res = solve(level, level.tiles.map((t) => t.r), { maxNodes: 500_000 });
  const solverBits = Math.log2(1 + res.nodes);
  const mechanics = mechanicsOf(level);
  const w = DIFFICULTY_WEIGHTS;
  const estimate =
    w.par * level.par +
    w.searchBits * searchBits +
    w.routes * (routes - 1) +
    w.interactions * interactions +
    w.mechanics * mechanics.length +
    w.solverBits * solverBits;
  return {
    par: level.par,
    searchBits: round(searchBits),
    routes,
    packages,
    interactions: round(interactions),
    waits,
    mechanics,
    solverBits: round(solverBits),
    cells: level.width * level.height,
    estimate: round(estimate),
  };
}

export interface CurveIssue {
  index: number;
  id: string;
  kind: 'spike' | 'new_mechanics';
  detail: string;
}

/** Maximum allowed jump over the hardest of the previous three levels. */
export const SPIKE_LIMIT = 9;
/** A level may introduce at most this many mechanics the player hasn't seen yet. */
export const MAX_NEW_MECHANICS = 2;

/** Checks an ordered campaign for unfair spikes and for too many new mechanics at once. */
export function checkCurve(levels: Level[], metrics: DifficultyMetrics[]): CurveIssue[] {
  const issues: CurveIssue[] = [];
  const seen = new Set<string>();
  for (let i = 0; i < levels.length; i++) {
    const m = metrics[i] as DifficultyMetrics;
    if (i > 0) {
      const prev = Math.max(...metrics.slice(Math.max(0, i - 3), i).map((x) => x.estimate));
      if (m.estimate - prev > SPIKE_LIMIT) {
        issues.push({ index: i, id: levels[i]!.id, kind: 'spike', detail: `estimate ${m.estimate} vs ${prev} in the previous three levels` });
      }
    }
    // Colour count is a scale, not a new mechanic, once two colours have been taught.
    const fresh = m.mechanics.filter((x) => !seen.has(x) && !(x.startsWith('colours:') && [...seen].some((s) => s.startsWith('colours:'))));
    if (i > 0 && fresh.length > MAX_NEW_MECHANICS) {
      issues.push({ index: i, id: levels[i]!.id, kind: 'new_mechanics', detail: `introduces ${fresh.join(', ')}` });
    }
    for (const x of m.mechanics) seen.add(x);
  }
  return issues;
}

function round(x: number): number {
  return Math.round(x * 10) / 10;
}
