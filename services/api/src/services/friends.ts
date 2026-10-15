import { randomInt } from 'node:crypto';
import { GENERATOR_VERSION, generateLevel, verifyReplay, type Level, type Move } from '@loopfactory/engine';
import type * as C from '@loopfactory/contracts';
import type { Prisma } from '@prisma/client';
import type { z } from 'zod';
import type { Db } from '../db';
import { isUniqueViolation, lockedTransaction } from '../db';
import { ApiError } from '../errors';
import type { DailyService } from './daily';
import { dateToUtc } from './daily';
import { publicLevel, type LevelService } from './levels';

/** Unambiguous alphabet (no 0/O, 1/I/L): codes are read aloud and typed by hand. */
export const CODE_ALPHABET = 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';
export const CODE_LENGTH = 8;
export const CHALLENGE_TTL_DAYS = 30;

type LevelRef = z.infer<typeof C.ChallengeLevelRef>;

export function newCode(): string {
  let s = '';
  for (let i = 0; i < CODE_LENGTH; i++) s += CODE_ALPHABET[randomInt(CODE_ALPHABET.length)];
  return s;
}

export function outcomeOf(mine: number, theirs: number): 'win' | 'tie' | 'lose' {
  return mine < theirs ? 'win' : mine === theirs ? 'tie' : 'lose';
}

/**
 * Friend challenges. The creator's solve and every attempt are re-simulated on the server, so a
 * comparison can only ever show verified rotation counts. Recipients play as silent guests — no
 * sign-up is required to accept a challenge.
 */
export class FriendChallengeService {
  constructor(
    private db: Db,
    private levels: LevelService,
    private daily: DailyService,
    private publicBaseUrl: string,
  ) {}

  /** Rebuild the exact puzzle a reference points to (never trusts a client-sent board). */
  async resolve(ref: LevelRef): Promise<Level> {
    switch (ref.type) {
      case 'campaign': {
        const found = await this.levels.get(ref.levelId);
        if (!found) throw new ApiError(404, 'level_not_found', 'Level not found');
        return found.level;
      }
      case 'daily': {
        const row = await this.db.dailyChallenge.findUnique({ where: { date: dateToUtc(ref.date) } });
        if (!row) throw new ApiError(404, 'daily_not_found', 'That daily puzzle is not available');
        return row.level as unknown as Level;
      }
      case 'generated': {
        if (ref.version !== GENERATOR_VERSION) throw new ApiError(409, 'generator_version_mismatch', 'Puzzle was made by a different generator version');
        const lvl = generateLevel(ref.seed, ref.tier);
        if (!lvl) throw new ApiError(422, 'level_not_generated', 'No puzzle for that seed');
        return lvl;
      }
    }
  }

  url(code: string): string {
    return this.publicBaseUrl ? `${this.publicBaseUrl}/c/${code}` : `/c/${code}`;
  }

  async create(playerId: string, ref: LevelRef, moves: Move[]) {
    const level = await this.resolve(ref);
    const verdict = verifyReplay(level, moves);
    if (!verdict.valid) throw new ApiError(422, 'invalid_solution', `Solution does not solve the puzzle (${verdict.error})`);
    const expiresAt = new Date(Date.now() + CHALLENGE_TTL_DAYS * 86400_000);
    for (let attempt = 0; attempt < 5; attempt++) {
      const code = newCode();
      try {
        await this.db.friendChallenge.create({
          data: {
            code,
            creatorId: playerId,
            levelRef: ref as unknown as Prisma.InputJsonValue,
            level: level as unknown as Prisma.InputJsonValue,
            creatorMoves: moves as unknown as Prisma.InputJsonValue,
            creatorRotations: verdict.rotations,
            expiresAt,
          },
        });
        return { code, url: this.url(code), rotations: verdict.rotations, expiresAt: expiresAt.toISOString() };
      } catch (e) {
        if (!isUniqueViolation(e)) throw e;
      }
    }
    throw new ApiError(503, 'code_exhausted', 'Could not allocate a challenge code, try again');
  }

  private async find(code: string) {
    const ch = await this.db.friendChallenge.findUnique({ where: { code }, include: { creator: { select: { displayName: true } } } });
    if (!ch || ch.expiresAt.getTime() < Date.now()) throw new ApiError(404, 'challenge_not_found', 'Challenge not found or expired');
    return ch;
  }

  /** Public view: the puzzle without its solution and without the creator's moves. */
  async view(code: string) {
    const ch = await this.find(code);
    const attempts = await this.db.friendChallengeAttempt.count({ where: { challengeId: ch.id } });
    return {
      code: ch.code,
      level: publicLevel(ch.level as unknown as Level, false),
      creatorName: ch.creator.displayName,
      creatorRotations: ch.creatorRotations,
      attempts,
      createdAt: ch.createdAt.toISOString(),
      expiresAt: ch.expiresAt.toISOString(),
    };
  }

  async attempt(playerId: string, code: string, moves: Move[]) {
    const ch = await this.find(code);
    if (ch.creatorId === playerId) throw new ApiError(409, 'own_challenge', 'You created this challenge');
    const verdict = verifyReplay(ch.level as unknown as Level, moves);
    if (!verdict.valid) {
      const prev = await this.db.friendChallengeAttempt.findUnique({ where: { challengeId_playerId: { challengeId: ch.id, playerId } } });
      return { valid: false, rotations: verdict.rotations, best: prev?.rotations ?? null, creatorRotations: ch.creatorRotations, outcome: null, error: verdict.error };
    }
    // Serialised per (challenge, player): the stored best is the minimum of every valid attempt and
    // `tries` counts each one, whatever order concurrent attempts commit in.
    const best = await lockedTransaction(this.db, [`fc:${ch.id}:${playerId}`], async (tx) => {
      const prev = await tx.friendChallengeAttempt.findUnique({ where: { challengeId_playerId: { challengeId: ch.id, playerId } } });
      if (!prev) {
        await tx.friendChallengeAttempt.create({ data: { challengeId: ch.id, playerId, rotations: verdict.rotations, moves: moves as unknown as Prisma.InputJsonValue } });
        return verdict.rotations;
      }
      const improved = verdict.rotations < prev.rotations;
      await tx.friendChallengeAttempt.update({
        where: { id: prev.id },
        data: { tries: { increment: 1 }, ...(improved ? { rotations: verdict.rotations, moves: moves as unknown as Prisma.InputJsonValue } : {}) },
      });
      return Math.min(prev.rotations, verdict.rotations);
    });
    return { valid: true, rotations: verdict.rotations, best, creatorRotations: ch.creatorRotations, outcome: outcomeOf(best, ch.creatorRotations), error: null };
  }

  /** Head-to-head table for everyone who played this code (the "friends leaderboard"). */
  async results(code: string, playerId: string | null, limit = 50) {
    const ch = await this.find(code);
    const rows = await this.db.friendChallengeAttempt.findMany({
      where: { challengeId: ch.id },
      orderBy: [{ rotations: 'asc' }, { updatedAt: 'asc' }],
      take: limit,
      include: { player: { select: { displayName: true } } },
    });
    const all = [
      { displayName: ch.creator.displayName, rotations: ch.creatorRotations, isMe: ch.creatorId === playerId, isCreator: true, at: ch.createdAt.getTime() },
      ...rows.map((r) => ({ displayName: r.player.displayName, rotations: r.rotations, isMe: r.playerId === playerId, isCreator: false, at: r.updatedAt.getTime() })),
    ].sort((a, b) => a.rotations - b.rotations || a.at - b.at);
    return {
      code: ch.code,
      creatorName: ch.creator.displayName,
      creatorRotations: ch.creatorRotations,
      entries: all.map((e, i) => ({ rank: i + 1, displayName: e.displayName, rotations: e.rotations, isMe: e.isMe, isCreator: e.isCreator })),
    };
  }
}

const esc = (s: string) => s.replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' })[c]!);

/**
 * Minimal landing page for challenge links (recipients without the app). It shows the challenge,
 * the code to type into the app, an app deep link, and store links when configured. No scripts,
 * no trackers. Deep links only open the app once Android intent filters / iOS associated domains
 * are configured for the production domain (docs/sharing.md).
 */
export function landingPage(v: { code: string; creatorName: string; creatorRotations: number; levelName: string; difficulty: string; par: number } | null, stores: { play: string; app: string }): string {
  const body = v
    ? `<p class="eyebrow">Loop Factory · friend challenge</p>
<h1>${esc(v.creatorName)} solved <em>${esc(v.levelName)}</em> in ${v.creatorRotations} rotations.</h1>
<p>Can you do better? It's a ${esc(v.difficulty)} puzzle (par ${v.par}).</p>
<p class="code">${esc(v.code)}</p>
<p>Open Loop Factory, tap <strong>Friend code</strong> and enter the code above.</p>
<p><a class="btn" href="loopfactory://challenge/${esc(v.code)}">Open in the app</a></p>`
    : `<p class="eyebrow">Loop Factory</p><h1>This challenge has expired or doesn't exist.</h1><p>Challenges last 30 days. Ask your friend to send a new one.</p>`;
  const storeLinks = [stores.play && `<a href="${esc(stores.play)}">Get it on Google Play</a>`, stores.app && `<a href="${esc(stores.app)}">Download on the App Store</a>`].filter(Boolean).join(' · ');
  return `<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>Loop Factory challenge</title><meta name="robots" content="noindex">
<style>body{margin:0;font-family:system-ui,sans-serif;background:#F7F5F0;color:#282B3C;display:flex;min-height:100vh;align-items:center;justify-content:center}
main{max-width:420px;margin:16px;padding:28px;background:#fff;border-radius:24px;box-shadow:0 6px 24px rgba(40,43,60,.08)}
.eyebrow{color:#5C6BC0;font-weight:700;text-transform:uppercase;font-size:13px;letter-spacing:.08em}h1{font-size:24px;line-height:1.3}
.code{font-size:40px;font-weight:800;letter-spacing:.12em;color:#5C6BC0;background:#EFEBE3;border-radius:16px;text-align:center;padding:12px}
.btn{display:block;text-align:center;background:#5C6BC0;color:#fff;padding:14px;border-radius:14px;text-decoration:none;font-weight:700}
footer{margin-top:20px;font-size:14px;color:#6F7287}</style></head>
<body><main>${body}${storeLinks ? `<footer>${storeLinks}</footer>` : ''}</main></body></html>`;
}
