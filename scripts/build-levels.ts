/**
 * Builds the curated campaign: parses/generates each entry, solves it, verifies the solution with
 * the simulation, and writes the shared level files consumed by the API and the Godot client.
 *   npm run levels:build          write files
 *   npm run levels:build -- --review   also print ASCII renders for manual review
 *   npm run levels:check          fail if committed files are stale (CI)
 */
import { readFileSync, writeFileSync, mkdirSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import {
  difficultyScore,
  generateLevel,
  isSolved,
  parseAscii,
  renderAscii,
  solve,
  validateBoard,
  verifyReplay,
  type Level,
} from '../packages/engine/src/index';
import { CONTENT_VERSION, CURATED } from './levels/curated-source';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const outputs = [resolve(root, 'packages/engine/levels/curated.json'), resolve(root, 'apps/game/data/levels/curated.json')];
const check = process.argv.includes('--check');
const review = process.argv.includes('--review');

const levels: Level[] = [];
const ids = new Set<string>();
for (const entry of CURATED) {
  if (ids.has(entry.id)) throw new Error(`Duplicate id ${entry.id}`);
  ids.add(entry.id);
  let level: Level;
  if ('ascii' in entry) {
    const board = parseAscii(entry.ascii);
    validateBoard(board);
    const start = board.tiles.map((t) => t.r);
    if (isSolved(board, start)) throw new Error(`${entry.id}: starts solved`);
    const res = solve(board, start, { maxNodes: 500_000, countCap: 20 });
    if (res.status !== 'solved' || !res.rotations) throw new Error(`${entry.id}: ${res.status}\n${renderAscii(board)}`);
    const paths = board.tiles.filter((t) => t.t === 'source').length;
    level = {
      id: entry.id,
      name: entry.name,
      version: CONTENT_VERSION,
      difficulty: entry.difficulty,
      difficultyScore: difficultyScore(board.tiles, res.minCost, paths),
      width: board.width,
      height: board.height,
      tiles: board.tiles,
      generator: null,
      par: res.minCost,
      solution: { rotations: res.rotations, moves: res.moves },
      solutionCount: res.solutionCount,
      solutionCountCapped: res.solutionCountCapped,
    };
  } else {
    const gen = generateLevel(entry.seed, entry.tier, { id: entry.id, name: entry.name });
    if (!gen) throw new Error(`${entry.id}: generator produced no level for seed ${entry.seed}`);
    level = { ...gen, version: CONTENT_VERSION };
  }
  if (entry.tip) level.tip = entry.tip;
  const verdict = verifyReplay(level, level.solution.moves);
  if (!verdict.valid) throw new Error(`${entry.id}: stored solution fails verification (${verdict.error})`);
  levels.push(level);
  if (review) {
    console.log(`\n${level.id} "${level.name}" ${level.difficulty} ${level.width}x${level.height} par=${level.par} score=${level.difficultyScore} solutions=${level.solutionCount}${level.solutionCountCapped ? '+' : ''}`);
    console.log(renderAscii(level));
    console.log('  solved:');
    console.log(renderAscii(level, level.solution.rotations));
  }
}

const json = JSON.stringify({ contentVersion: CONTENT_VERSION, levels }, null, 1) + '\n';
let stale = false;
for (const file of outputs) {
  if (check) {
    let current = '';
    try {
      current = readFileSync(file, 'utf8');
    } catch {
      /* missing */
    }
    if (current !== json) {
      console.error(`Stale: ${file}. Run npm run levels:build`);
      stale = true;
    }
  } else {
    mkdirSync(dirname(file), { recursive: true });
    writeFileSync(file, json);
  }
}
// Achievements definitions are shared with the client.
const achSrc = resolve(root, 'packages/contracts/data/achievements.json');
const achDst = resolve(root, 'apps/game/data/achievements.json');
const achJson = readFileSync(achSrc, 'utf8');
if (check) {
  let current = '';
  try {
    current = readFileSync(achDst, 'utf8');
  } catch {
    /* missing */
  }
  if (current !== achJson) {
    console.error(`Stale: ${achDst}. Run npm run levels:build`);
    stale = true;
  }
} else {
  writeFileSync(achDst, achJson);
}
if (stale) process.exit(1);
console.log(`${check ? 'Verified' : 'Wrote'} ${levels.length} curated levels (content v${CONTENT_VERSION}).`);
