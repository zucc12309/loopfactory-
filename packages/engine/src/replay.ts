import { applyMoves, IllegalMoveError, validateBoard, type Board, type Move } from './level';
import { simulate, type FailureReason } from './simulation';

export interface ReplayVerdict {
  valid: boolean;
  /** Rotations counted for scoring: the number of moves in the replay. */
  rotations: number;
  error: 'illegal_move' | 'not_solved' | 'too_many_moves' | 'invalid_board' | null;
  failure: FailureReason | null;
}

export const MAX_REPLAY_MOVES = 500;

/**
 * Authoritative replay validation (used server-side for competitive scores).
 * The score is derived from the replay itself — never from client-reported counters.
 */
export function verifyReplay(board: Board, moves: readonly Move[]): ReplayVerdict {
  try {
    validateBoard(board);
  } catch {
    return { valid: false, rotations: 0, error: 'invalid_board', failure: null };
  }
  if (moves.length > MAX_REPLAY_MOVES) return { valid: false, rotations: moves.length, error: 'too_many_moves', failure: null };
  let rotations: number[];
  try {
    rotations = applyMoves(board, moves);
  } catch (e) {
    if (e instanceof IllegalMoveError) return { valid: false, rotations: moves.length, error: 'illegal_move', failure: null };
    throw e;
  }
  const sim = simulate(board, rotations, { recordFrames: false });
  if (!sim.success) return { valid: false, rotations: moves.length, error: 'not_solved', failure: sim.reason };
  return { valid: true, rotations: moves.length, error: null, failure: null };
}
