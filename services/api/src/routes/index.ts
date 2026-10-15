import * as C from '@loopfactory/contracts';
import type { Level } from '@loopfactory/engine';
import type { Prisma } from '@prisma/client';
import { z } from 'zod';
import type { Config } from '../config';
import type { Db } from '../db';
import { isUniqueViolation } from '../db';
import { ApiError } from '../errors';
import { defineRoute, requirePlayer, type AnyRoute } from '../http';
import { makeLimiter } from '../middleware/rateLimit';
import { ACHIEVEMENTS, playerStats } from '../services/achievements';
import { DailyService, dateToUtc, todayUtc } from '../services/daily';
import type { IdentityVerifier } from '../services/identity';
import { isoWeek, readBoard } from '../services/leaderboards';
import { CAMPAIGN_PACK, LevelService, publicLevel } from '../services/levels';
import { guestName, isNameAllowed } from '../services/names';
import { PrivacyService } from '../services/privacy';
import { ProgressService } from '../services/progress';
import type { PurchaseVerifier } from '../services/purchases';
import type { TokenService } from '../services/tokens';

export interface Deps {
  db: Db;
  config: Config;
  tokens: TokenService;
  identity: IdentityVerifier;
  purchases: PurchaseVerifier;
}

export const DEFAULT_REMOTE_CONFIG = {
  hintsEnabled: true,
  rewardedAdsEnabled: false,
  minSupportedClientVersion: '0.1.0',
  endlessEnabled: true,
  dailyEnabled: true,
  motd: '',
};

export function buildRoutes(d: Deps): AnyRoute[] {
  const { db, config } = d;
  const levels = new LevelService(db);
  const progress = new ProgressService(db, levels);
  const daily = new DailyService(db, config.dailySeedSecret);
  const privacy = new PrivacyService(db, config.privacySalt);
  const off = config.rateLimitDisabled;
  const guestLimit = makeLimiter({ name: 'guest', windowMs: 3600_000, limit: 30, disabled: off });
  const authLimit = makeLimiter({ name: 'auth', windowMs: 60_000, limit: 30, disabled: off });
  const syncLimit = makeLimiter({ name: 'sync', windowMs: 60_000, limit: 60, byPlayer: true, disabled: off });
  const submitLimit = makeLimiter({ name: 'submit', windowMs: 60_000, limit: 20, byPlayer: true, disabled: off });
  const privacyLimit = makeLimiter({ name: 'privacy', windowMs: 3600_000, limit: 10, byPlayer: true, disabled: off });

  const publicPlayer = (p: { id: string; displayName: string }) => ({ id: p.id, displayName: p.displayName });

  return [
    // ------------------------------------------------------------ auth
    defineRoute({
      method: 'post', path: '/auth/guest', tag: 'auth', auth: 'none', status: 201, rateLimit: guestLimit,
      summary: 'Create an anonymous guest account and receive server-issued credentials',
      body: C.GuestRequest, response: C.GuestResponse,
      handler: async () => {
        const player = await db.player.create({ data: { displayName: guestName() } });
        await db.playerAuthIdentity.create({ data: { playerId: player.id, provider: 'guest', subject: player.id } });
        const tokens = await d.tokens.issue(player.id);
        return { player: publicPlayer(player), ...tokens };
      },
    }),
    defineRoute({
      method: 'post', path: '/auth/refresh', tag: 'auth', auth: 'none', rateLimit: authLimit,
      summary: 'Rotate a refresh token (single use; reuse revokes the session family)',
      body: C.RefreshRequest, response: C.TokenResponse,
      handler: async ({ body }) => {
        const { playerId, tokens } = await d.tokens.rotate(body.refreshToken);
        await db.player.update({ where: { id: playerId }, data: { lastSeenAt: new Date() } });
        return tokens;
      },
    }),
    defineRoute({
      method: 'post', path: '/auth/link', tag: 'auth', auth: 'required', rateLimit: authLimit,
      summary: 'Link a Google/Apple identity to this account, or switch to the account that already owns it (restore after reinstall)',
      body: C.LinkRequest, response: C.LinkResponse,
      handler: async ({ body, playerId }) => {
        const me = requirePlayer(playerId);
        const ident = await d.identity.verify(body.provider, body.idToken);
        const existing = await db.playerAuthIdentity.findUnique({ where: { provider_subject: { provider: ident.provider, subject: ident.subject } }, include: { player: true } });
        if (!existing) {
          const already = await db.playerAuthIdentity.findFirst({ where: { playerId: me, provider: ident.provider } });
          if (already) throw new ApiError(409, 'provider_already_linked', `This account already has a different ${ident.provider} identity`);
          try {
            await db.playerAuthIdentity.create({ data: { playerId: me, provider: ident.provider, subject: ident.subject, email: ident.email } });
          } catch (e) {
            if (isUniqueViolation(e)) throw new ApiError(409, 'identity_in_use', 'Identity was just linked elsewhere; retry');
            throw e;
          }
          const p = await db.player.findUniqueOrThrow({ where: { id: me } });
          return { mode: 'linked' as const, player: publicPlayer(p) };
        }
        if (existing.playerId === me) return { mode: 'already_linked' as const, player: publicPlayer(existing.player) };
        if (body.onConflict !== 'switch') throw new ApiError(409, 'identity_in_use', 'This identity belongs to another Loop Factory account', { canSwitch: true });
        const tokens = await d.tokens.issue(existing.playerId);
        return { mode: 'switched' as const, player: publicPlayer(existing.player), tokens };
      },
    }),
    defineRoute({
      method: 'post', path: '/auth/logout', tag: 'auth', auth: 'required',
      summary: 'Revoke the refresh-token family of this session', body: C.LogoutRequest, response: z.undefined(),
      handler: async ({ body, playerId }) => {
        await d.tokens.revokeByToken(body.refreshToken, requirePlayer(playerId));
        return undefined;
      },
    }),

    // ------------------------------------------------------------ player
    defineRoute({
      method: 'get', path: '/player/me', tag: 'player', auth: 'required', summary: 'Current player profile and stats', response: C.PlayerMe,
      handler: async ({ playerId }) => {
        const id = requirePlayer(playerId);
        const p = await db.player.findUnique({ where: { id }, include: { identities: { select: { provider: true } } } });
        if (!p) throw new ApiError(404, 'player_not_found', 'Player not found');
        return { id: p.id, displayName: p.displayName, createdAt: p.createdAt.toISOString(), linkedProviders: p.identities.map((i) => i.provider).filter((x) => x !== 'guest'), stats: await playerStats(db, id) };
      },
    }),
    defineRoute({
      method: 'patch', path: '/player/me', tag: 'player', auth: 'required', summary: 'Update display name', body: C.PatchPlayerRequest, response: C.PublicPlayer,
      handler: async ({ body, playerId }) => {
        if (!isNameAllowed(body.displayName)) throw new ApiError(422, 'name_not_allowed', 'Please choose a different name');
        const p = await db.player.update({ where: { id: requirePlayer(playerId) }, data: { displayName: body.displayName } });
        return publicPlayer(p);
      },
    }),
    defineRoute({
      method: 'delete', path: '/player/me', tag: 'player', auth: 'required', rateLimit: privacyLimit, summary: 'Delete account and all associated data', response: z.undefined(),
      handler: async ({ playerId }) => {
        await privacy.erase(requirePlayer(playerId));
        return undefined;
      },
    }),

    // ------------------------------------------------------------ progress
    defineRoute({
      method: 'get', path: '/progress', tag: 'progress', auth: 'required', summary: 'Full progress snapshot for merge', response: C.Snapshot,
      handler: async ({ playerId }) => progress.snapshot(requirePlayer(playerId)),
    }),
    defineRoute({
      method: 'post', path: '/progress/sync', tag: 'progress', auth: 'required', rateLimit: syncLimit,
      summary: 'Upload queued offline operations (idempotent by opId) and receive the merged snapshot',
      body: C.SyncRequest, response: C.SyncResponse,
      handler: async ({ body, playerId }) => {
        const id = requirePlayer(playerId);
        const results = await progress.sync(id, body.operations);
        await db.player.update({ where: { id }, data: { lastSeenAt: new Date() } });
        return { results, snapshot: await progress.snapshot(id) };
      },
    }),
    defineRoute({
      method: 'get', path: '/progress/history', tag: 'progress', auth: 'required', summary: 'Completion history, newest first', query: C.HistoryQuery, response: C.HistoryResponse,
      handler: async ({ query, playerId }) => {
        const rows = await db.playerLevelProgress.findMany({
          where: { playerId: requirePlayer(playerId), ...(query.before ? { lastCompletedAt: { lt: new Date(query.before) } } : {}) },
          orderBy: { lastCompletedAt: 'desc' },
          take: query.limit + 1,
        });
        const page = rows.slice(0, query.limit);
        return {
          items: page.map((p) => ({ levelId: p.levelKey, kind: p.kind, bestRotations: p.bestRotations, par: p.par, verified: p.verified, completedAt: p.lastCompletedAt.getTime(), completions: p.completions })),
          nextBefore: rows.length > query.limit ? page[page.length - 1]!.lastCompletedAt.getTime() : null,
        };
      },
    }),

    // ------------------------------------------------------------ levels (specific paths before :id)
    defineRoute({
      method: 'get', path: '/levels/packs', tag: 'levels', auth: 'none', summary: 'Level packs', response: C.PacksResponse,
      handler: async ({ res }) => {
        res.setHeader('Cache-Control', 'public, max-age=3600');
        const packs = await db.levelPack.findMany({ orderBy: { ordinal: 'asc' }, include: { levels: { select: { id: true }, orderBy: { ordinal: 'asc' } } } });
        return { packs: packs.map((p) => ({ id: p.id, name: p.name, description: p.description, levelIds: p.levels.map((l) => l.id) })) };
      },
    }),
    defineRoute({
      method: 'get', path: '/levels', tag: 'levels', auth: 'none', summary: 'List levels (cursor pagination)', query: C.LevelsQuery, response: C.LevelsResponse,
      handler: async ({ query, res }) => {
        res.setHeader('Cache-Control', 'public, max-age=300');
        const rows = await db.level.findMany({
          where: { packId: query.pack ?? CAMPAIGN_PACK, ...(query.difficulty ? { difficulty: query.difficulty } : {}), ...(query.cursor ? { id: { gt: query.cursor } } : {}) },
          orderBy: { id: 'asc' },
          take: query.limit + 1,
        });
        const page = rows.slice(0, query.limit);
        return {
          levels: page.map((l) => ({ id: l.id, name: l.name, difficulty: l.difficulty as z.infer<typeof C.Difficulty>, par: l.par, packId: l.packId, ordinal: l.ordinal, contentVersion: l.contentVersion })),
          nextCursor: rows.length > query.limit ? page[page.length - 1]!.id : null,
        };
      },
    }),
    defineRoute({
      method: 'get', path: '/levels/:id', tag: 'levels', auth: 'none', params: { id: 'Level id' }, summary: 'Full level definition', response: C.LevelSchema,
      handler: async ({ req, res }) => {
        const id = z.string().max(64).parse(req.params.id);
        const found = await levels.get(id);
        if (!found) throw new ApiError(404, 'level_not_found', 'Level not found');
        res.setHeader('Cache-Control', 'public, max-age=3600');
        return publicLevel(found.level, true);
      },
    }),

    // ------------------------------------------------------------ daily challenges
    defineRoute({
      method: 'get', path: '/challenges/daily', tag: 'daily', auth: 'none', summary: "Today's (or a recent) official daily puzzle", query: C.DailyQuery, response: C.DailyResponse,
      handler: async ({ query, res }) => {
        const date = query.date ?? todayUtc();
        daily.assertAvailable(date);
        const ch = await daily.getOrCreate(date);
        res.setHeader('Cache-Control', 'public, max-age=600');
        return {
          date,
          tier: ch.tier as z.infer<typeof C.Difficulty>,
          generatorVersion: ch.generatorVersion,
          level: publicLevel(ch.level as unknown as Level, false),
          par: ch.par,
          closesAt: daily.closesAt(date).toISOString(),
        };
      },
    }),
    defineRoute({
      method: 'post', path: '/challenges/daily/submit', tag: 'daily', auth: 'required', rateLimit: submitLimit,
      summary: 'Submit a move replay; the server re-simulates it and ranks by verified rotation count',
      body: C.DailySubmitRequest, response: C.DailySubmitResponse,
      handler: async ({ body, playerId }) => daily.submit(requirePlayer(playerId), body.date, body.moves, body.submissionId),
    }),
    defineRoute({
      method: 'get', path: '/challenges/daily/leaderboard', tag: 'daily', auth: 'optional', summary: 'Daily leaderboard', query: C.LeaderboardQuery, response: C.LeaderboardResponse,
      handler: async ({ query, playerId }) => readBoard(db, `daily:${query.date ?? todayUtc()}`, query.limit, playerId),
    }),

    // ------------------------------------------------------------ leaderboards
    defineRoute({
      method: 'get', path: '/leaderboards/global', tag: 'leaderboards', auth: 'optional', summary: 'All-time ranking by verified campaign solves', query: C.LeaderboardQuery, response: C.LeaderboardResponse,
      handler: async ({ query, playerId }) => readBoard(db, 'global', query.limit, playerId),
    }),
    defineRoute({
      method: 'get', path: '/leaderboards/weekly', tag: 'leaderboards', auth: 'optional', summary: 'ISO-week ranking by dailies solved, then rotations', query: C.LeaderboardQuery, response: C.LeaderboardResponse,
      handler: async ({ query, playerId }) => readBoard(db, `weekly:${query.week ?? isoWeek(new Date())}`, query.limit, playerId),
    }),
    defineRoute({
      method: 'get', path: '/leaderboards/daily', tag: 'leaderboards', auth: 'optional', summary: 'Daily ranking (alias of /challenges/daily/leaderboard)', query: C.LeaderboardQuery, response: C.LeaderboardResponse,
      handler: async ({ query, playerId }) => readBoard(db, `daily:${query.date ?? todayUtc()}`, query.limit, playerId),
    }),

    // ------------------------------------------------------------ achievements
    defineRoute({
      method: 'get', path: '/achievements', tag: 'achievements', auth: 'none', summary: 'Achievement definitions', response: C.AchievementsResponse,
      handler: async () => ({ achievements: ACHIEVEMENTS }),
    }),
    defineRoute({
      method: 'get', path: '/achievements/me', tag: 'achievements', auth: 'required', summary: 'Achievements unlocked by the current player', response: C.MyAchievementsResponse,
      handler: async ({ playerId }) => {
        const rows = await db.playerAchievement.findMany({ where: { playerId: requirePlayer(playerId) }, orderBy: { unlockedAt: 'asc' } });
        return { achievements: rows.map((r) => ({ id: r.achievementId, unlockedAt: r.unlockedAt.toISOString() })) };
      },
    }),

    // ------------------------------------------------------------ remote config
    defineRoute({
      method: 'get', path: '/config', tag: 'config', auth: 'none', summary: 'Active remote configuration', response: C.ConfigResponse,
      handler: async ({ req, res }) => {
        const row = await db.remoteConfigVersion.findFirst({ where: { active: true }, orderBy: { version: 'desc' } });
        const body = { version: row?.version ?? 0, config: { ...DEFAULT_REMOTE_CONFIG, ...((row?.config as object) ?? {}) } };
        const etag = `"cfg-${body.version}"`;
        res.setHeader('ETag', etag);
        res.setHeader('Cache-Control', 'public, max-age=300');
        if (req.headers['if-none-match'] === etag) {
          res.status(304).end();
          return undefined;
        }
        return body;
      },
    }),

    // ------------------------------------------------------------ privacy
    defineRoute({
      method: 'get', path: '/privacy/export', tag: 'privacy', auth: 'required', rateLimit: privacyLimit, summary: 'Export all personal data as JSON', response: z.record(z.unknown()),
      handler: async ({ playerId }) => privacy.export(requirePlayer(playerId)),
    }),
    defineRoute({
      method: 'post', path: '/privacy/delete-request', tag: 'privacy', auth: 'required', rateLimit: privacyLimit, summary: 'Erase the account and all data (immediate, irreversible)', body: C.DeleteRequest, response: C.DeleteResponse,
      handler: async ({ playerId }) => ({ requestId: await privacy.erase(requirePlayer(playerId)), status: 'completed' as const }),
    }),

    // ------------------------------------------------------------ purchases
    defineRoute({
      method: 'post', path: '/purchases/verify', tag: 'purchases', auth: 'required', rateLimit: submitLimit, summary: 'Verify a store purchase server-side and grant the entitlement', body: C.PurchaseVerifyRequest, response: C.EntitlementsResponse,
      handler: async ({ body, playerId }) => {
        const id = requirePlayer(playerId);
        const v = await d.purchases.verify(body.store, body.productId, body.purchaseToken);
        const existing = await db.purchaseEntitlement.findUnique({ where: { store_transactionId: { store: body.store, transactionId: v.transactionId } } });
        if (existing && existing.playerId !== id) throw new ApiError(409, 'purchase_owned_elsewhere', 'This purchase is linked to another account; restore it from that account');
        if (!existing) await db.purchaseEntitlement.create({ data: { playerId: id, store: body.store, productId: v.productId, transactionId: v.transactionId, status: v.status } });
        return entitlements(db, id);
      },
    }),
    defineRoute({
      method: 'get', path: '/purchases/entitlements', tag: 'purchases', auth: 'required', summary: 'Active entitlements (restore purchases)', response: C.EntitlementsResponse,
      handler: async ({ playerId }) => entitlements(db, requirePlayer(playerId)),
    }),
  ];
}

async function entitlements(db: Db, playerId: string) {
  const rows = await db.purchaseEntitlement.findMany({ where: { playerId, status: 'active' }, orderBy: { verifiedAt: 'asc' } });
  return { entitlements: rows.map((r) => ({ productId: r.productId, store: r.store, status: r.status, verifiedAt: r.verifiedAt.toISOString() })) };
}

export type { Prisma };
export { dateToUtc };
