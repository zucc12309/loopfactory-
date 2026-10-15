/**
 * Source of truth for the curated campaign. Hand-designed teaching levels are authored in the ASCII
 * format (see packages/engine/src/ascii.ts); later levels reference generator seeds that were
 * reviewed by hand (ASCII render + par + solution count) before being added here.
 * Run `npm run levels:build` after editing; CI runs `npm run levels:check`.
 */
import type { Difficulty } from '../../packages/engine/src/index';

export type CuratedEntry =
  | { id: string; name: string; difficulty: Difficulty; ascii: string; tip?: string }
  | { id: string; name: string; tier: Difficulty; seed: number; tip?: string };

export const CONTENT_VERSION = 1;

export const CURATED: CuratedEntry[] = [
  {
    id: 'c01', name: 'First Tap', difficulty: 'beginner',
    tip: 'Tap a belt to turn it. Press Run when the path is ready.',
    ascii: `
      #   .  .  #
      S1a I0 I1 Da
      #   .  .  #`,
  },
  {
    id: 'c02', name: 'Bend', difficulty: 'beginner',
    tip: 'Corners turn packages. Aim them toward the matching dock.',
    ascii: `
      S2a .  .
      L3  I1 L1
      .   .  Da`,
  },
  {
    id: 'c03', name: 'Detour', difficulty: 'beginner',
    tip: 'Not every belt is part of the route.',
    ascii: `
      S1a I1 L0 .
      #   #  I1 .
      Da  I0 L3 L0
      .   .  .  .`,
  },
  {
    id: 'c04', name: 'Pinned', difficulty: 'beginner',
    tip: 'Belts with a pin are locked in place. Build around them.',
    ascii: `
      S2a .   .   .
      L2  I1! L1  .
      .   L1  I0! .
      .   I0  L3  Da`,
  },
  {
    id: 'c05', name: 'Convoy', difficulty: 'easy',
    tip: 'Some sources send several packages. Every one must arrive.',
    ascii: `
      S1a3 L1 .  #
      .    L3 I0 L0
      #    .  .  I1
      .    .  L2 Da`,
  },
  {
    id: 'c06', name: 'Two Colors', difficulty: 'easy',
    tip: 'Packages only accept a dock of their own color.',
    ascii: `
      S2a .   .   S2b
      I1  L0  L2  I1
      L2  L1  L0  L1
      .   Da  Db  .`,
  },
  {
    id: 'c07', name: 'Crossroads', difficulty: 'easy',
    tip: 'Crossings let routes pass through each other.',
    ascii: `
      L1  S2a L0  .
      S1b X   I0  Db
      .   I1  L2  .
      #   Da  .   I0`,
  },
  {
    id: 'c08', name: 'Junction', difficulty: 'easy',
    tip: 'Junctions send packages straight when they can — otherwise to the right.',
    ascii: `
      S1a T0 #
      .   I1 .
      .   L1 Da`,
  },
  {
    id: 'c09', name: 'Counter-turn', difficulty: 'easy',
    tip: 'Long-press a belt to turn it the other way. It still counts as one move.',
    ascii: `
      S1a L3 .
      #   L1 L3
      .   .  Da`,
  },
  // ---- Reviewed generator levels (gen-1) ----
  { id: 'c10', name: 'Warm Up', tier: 'beginner', seed: 1008 },
  { id: 'c11', name: 'Side Step', tier: 'beginner', seed: 1023 },
  { id: 'c12', name: 'Long Way Round', tier: 'beginner', seed: 1013 },
  { id: 'c13', name: 'Switchback', tier: 'beginner', seed: 1001 },
  { id: 'c14', name: 'Loading Bay', tier: 'easy', seed: 1009 },
  { id: 'c15', name: 'Zig Zag', tier: 'easy', seed: 1017 },
  { id: 'c16', name: 'Night Shift', tier: 'easy', seed: 1006 },
  { id: 'c17', name: 'Backlog', tier: 'easy', seed: 1018 },
  { id: 'c18', name: 'Assembly', tier: 'easy', seed: 1000 },
  { id: 'c19', name: 'Serpentine', tier: 'easy', seed: 1019 },
  { id: 'c20', name: 'Pair Up', tier: 'medium', seed: 1022, tip: 'Two routes now. Plan both before you press Run.' },
  { id: 'c21', name: 'Sorting Room', tier: 'medium', seed: 1024 },
  { id: 'c22', name: 'Twin Lines', tier: 'medium', seed: 1003 },
  { id: 'c23', name: 'Dispatch', tier: 'medium', seed: 1010 },
  { id: 'c24', name: 'Rush Hour', tier: 'medium', seed: 1016 },
  { id: 'c25', name: 'Overtime', tier: 'medium', seed: 1012 },
  { id: 'c26', name: 'Interchange', tier: 'hard', seed: 1006, tip: 'Packages wait their turn at busy tiles. The earliest one goes first.' },
  { id: 'c27', name: 'Flyover', tier: 'hard', seed: 1001 },
  { id: 'c28', name: 'Bottleneck', tier: 'hard', seed: 1020 },
  { id: 'c29', name: 'Gridlock', tier: 'hard', seed: 1003 },
  { id: 'c30', name: 'Freight', tier: 'hard', seed: 1018 },
  { id: 'c31', name: 'Tri-Color', tier: 'expert', seed: 1012 },
  { id: 'c32', name: 'Clockwork', tier: 'expert', seed: 1004 },
  { id: 'c33', name: 'Mainframe', tier: 'expert', seed: 1021 },
  { id: 'c34', name: 'Loop Factory', tier: 'expert', seed: 1016 },
];
