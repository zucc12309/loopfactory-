import type { Board } from './level';
import type { Tile, TileType } from './tiles';

/**
 * Compact text format for authoring curated levels, one token per cell, rows separated by newlines:
 *   .      empty            #      blocked
 *   I<r>   straight         L<r>   corner        T<r>  tee       X  cross
 *   S<r><c>[n]  source facing r, color c (a-d), optional package count
 *   D<c>   destination of color c
 *   suffix ! = locked
 * Example: "S1a L2 . D a" — rotations are the *starting* (scrambled) orientations.
 */
const COLORS = 'abcd';

export function parseAscii(text: string): Board {
  const rows = text
    .trim()
    .split('\n')
    .map((r) => r.trim())
    .filter((r) => r.length > 0)
    .map((r) => r.split(/\s+/));
  const height = rows.length;
  const width = rows[0]?.length ?? 0;
  const tiles: Tile[] = [];
  for (const row of rows) {
    if (row.length !== width) throw new Error(`Ragged row: ${row.join(' ')}`);
    for (const tok of row) tiles.push(parseToken(tok));
  }
  return { width, height, tiles };
}

function parseToken(raw: string): Tile {
  const locked = raw.endsWith('!');
  const tok = locked ? raw.slice(0, -1) : raw;
  const head = tok[0];
  const digit = (s: string | undefined) => {
    const n = Number(s);
    if (!Number.isInteger(n) || n < 0 || n > 3) throw new Error(`Bad rotation in token ${raw}`);
    return n;
  };
  const color = (s: string | undefined) => {
    const c = COLORS.indexOf(s ?? '');
    if (c < 0) throw new Error(`Bad color in token ${raw}`);
    return c;
  };
  let tile: Tile;
  switch (head) {
    case '.':
      tile = { t: 'empty', r: 0 };
      break;
    case '#':
      tile = { t: 'blocked', r: 0 };
      break;
    case 'I':
    case 'L':
    case 'T': {
      const type: TileType = head === 'I' ? 'straight' : head === 'L' ? 'corner' : 'tee';
      tile = { t: type, r: digit(tok[1]) };
      break;
    }
    case 'X':
      tile = { t: 'cross', r: 0 };
      break;
    case 'S': {
      tile = { t: 'source', r: digit(tok[1]), c: color(tok[2]) };
      if (tok.length > 3) tile.n = Number(tok.slice(3));
      break;
    }
    case 'D':
      tile = { t: 'dest', r: 0, c: color(tok[1]) };
      break;
    default:
      throw new Error(`Unknown token ${raw}`);
  }
  if (locked && tile.t !== 'source' && tile.t !== 'dest') tile.l = true;
  return tile;
}

const GLYPHS: Record<string, string[]> = {
  straight: ['│', '─', '│', '─'],
  corner: ['└', '┌', '┐', '┘'],
  tee: ['├', '┬', '┤', '┴'],
};
const ARROWS = ['↑', '→', '↓', '←'];

/** Human-readable rendering used in reviews, logs and failing-test output. */
export function renderAscii(board: Board, rotations: readonly number[] = board.tiles.map((t) => t.r)): string {
  const lines: string[] = [];
  for (let y = 0; y < board.height; y++) {
    let line = '';
    for (let x = 0; x < board.width; x++) {
      const i = y * board.width + x;
      const t = board.tiles[i]!;
      const r = rotations[i]!;
      let g: string;
      switch (t.t) {
        case 'empty': g = ' · '; break;
        case 'blocked': g = '███'; break;
        case 'cross': g = '─┼─'; break;
        case 'source': g = `S${ARROWS[r]}${COLORS[t.c ?? 0]}`; break;
        case 'dest': g = `[${COLORS[t.c ?? 0]}]`; break;
        default: {
          const ch = GLYPHS[t.t]![r]!;
          g = (t.l ? '*' : ' ') + ch + ' ';
        }
      }
      line += g;
    }
    lines.push(line);
  }
  return lines.join('\n');
}

/** Serialize a board back to the authoring format. */
export function toAscii(board: Board, rotations: readonly number[] = board.tiles.map((t) => t.r)): string {
  const rows: string[] = [];
  for (let y = 0; y < board.height; y++) {
    const toks: string[] = [];
    for (let x = 0; x < board.width; x++) {
      const i = y * board.width + x;
      const t = board.tiles[i]!;
      const r = rotations[i]!;
      const lock = t.l ? '!' : '';
      switch (t.t) {
        case 'empty': toks.push('.'); break;
        case 'blocked': toks.push('#'); break;
        case 'straight': toks.push(`I${r}${lock}`); break;
        case 'corner': toks.push(`L${r}${lock}`); break;
        case 'tee': toks.push(`T${r}${lock}`); break;
        case 'cross': toks.push('X'); break;
        case 'source': toks.push(`S${r}${COLORS[t.c ?? 0]}${(t.n ?? 1) !== 1 ? t.n : ''}`); break;
        case 'dest': toks.push(`D${COLORS[t.c ?? 0]}`); break;
      }
    }
    rows.push(toks.join(' '));
  }
  return rows.join('\n');
}
