import { z } from 'zod';

/** API version prefix. Breaking changes require /api/v2. */
export const API_PREFIX = '/api/v1';

// ---------------------------------------------------------------- primitives

export const Uuid = z.string().uuid();
export const IsoDate = z.string().regex(/^\d{4}-\d{2}-\d{2}$/, 'Expected YYYY-MM-DD');
export const MoveSchema = z.tuple([z.number().int().min(0).max(143), z.union([z.literal(1), z.literal(-1)])]);
export const MovesSchema = z.array(MoveSchema).max(500);
export const DisplayName = z
  .string()
  .trim()
  .min(3)
  .max(20)
  .regex(/^[\p{L}\p{N} _.-]+$/u, 'Letters, numbers, spaces, _ . - only');

export const ErrorResponse = z.object({
  error: z.object({
    code: z.string(),
    message: z.string(),
    requestId: z.string().optional(),
    details: z.unknown().optional(),
  }),
});

// ---------------------------------------------------------------- auth

export const PublicPlayer = z.object({ id: Uuid, displayName: z.string() });

export const TokenResponse = z.object({
  accessToken: z.string(),
  accessTokenExpiresIn: z.number().int(),
  refreshToken: z.string(),
});

export const GuestRequest = z.object({ platform: z.string().max(32).optional() }).strict();
export const GuestResponse = TokenResponse.extend({ player: PublicPlayer });
export const RefreshRequest = z.object({ refreshToken: z.string().min(20).max(200) }).strict();
export const LinkRequest = z
  .object({
    provider: z.enum(['google', 'apple', 'dev']),
    idToken: z.string().min(1).max(4096),
    onConflict: z.enum(['fail', 'switch']).default('fail'),
  })
  .strict();
export const LinkResponse = z.object({
  mode: z.enum(['linked', 'already_linked', 'switched']),
  player: PublicPlayer,
  tokens: TokenResponse.optional(),
});
export const LogoutRequest = z.object({ refreshToken: z.string().min(20).max(200) }).strict();

// ---------------------------------------------------------------- player

export const StatsSchema = z.object({
  campaign: z.number().int(),
  perfect: z.number().int(),
  dailies: z.number().int(),
  endless: z.number().int(),
});
export const PlayerMe = z.object({
  id: Uuid,
  displayName: z.string(),
  createdAt: z.string(),
  linkedProviders: z.array(z.string()),
  stats: StatsSchema,
});
export const PatchPlayerRequest = z.object({ displayName: DisplayName }).strict();

// ---------------------------------------------------------------- progress & sync

export const SettingsSchema = z
  .object({
    sfx: z.boolean().optional(),
    haptics: z.boolean().optional(),
    reducedMotion: z.boolean().optional(),
    colorblind: z.boolean().optional(),
    analytics: z.boolean().optional(),
    analyticsAsked: z.boolean().optional(),
    cloudSync: z.boolean().optional(),
    updatedAt: z.number().int().nonnegative().optional(),
  })
  .strip();

export const GeneratorRef = z.object({ version: z.string().max(16), seed: z.number().int().nonnegative(), tier: z.enum(['beginner', 'easy', 'medium', 'hard', 'expert']) });

export const LevelCompletePayload = z.object({
  kind: z.enum(['campaign', 'endless']),
  levelId: z.string().min(1).max(96),
  contentVersion: z.number().int().min(1),
  moves: MovesSchema.nullable(),
  rotations: z.number().int().min(0).max(500),
  hints: z.number().int().min(0).max(1000).default(0),
  completedAt: z.number().int().nonnegative(),
  generator: GeneratorRef.optional(),
});
export const SettingsPayload = z.object({ settings: SettingsSchema, updatedAt: z.number().int().nonnegative() });
export const ActivePuzzlePayload = z.object({
  kind: z.enum(['campaign', 'endless', 'daily', 'offline_daily']),
  levelId: z.string().min(1).max(96),
  rotations: z.array(z.number().int().min(0).max(3)).max(144),
  history: MovesSchema,
  updatedAt: z.number().int().nonnegative(),
});

export const SyncOperation = z.discriminatedUnion('type', [
  z.object({ opId: z.string().min(8).max(64), type: z.literal('level_complete'), payload: LevelCompletePayload, clientTs: z.number().int() }),
  z.object({ opId: z.string().min(8).max(64), type: z.literal('settings'), payload: SettingsPayload, clientTs: z.number().int() }),
  z.object({ opId: z.string().min(8).max(64), type: z.literal('active_puzzle'), payload: ActivePuzzlePayload, clientTs: z.number().int() }),
]);
export const SyncRequest = z.object({ operations: z.array(SyncOperation).max(100) }).strict();

export const ProgressEntry = z.object({
  levelId: z.string(),
  kind: z.string(),
  bestRotations: z.number().int(),
  par: z.number().int(),
  verified: z.boolean(),
  completedAt: z.number().int(),
});
export const Snapshot = z.object({
  progress: z.array(ProgressEntry),
  settings: SettingsSchema.nullable(),
  activePuzzle: ActivePuzzlePayload.nullable(),
  stats: StatsSchema,
  achievements: z.array(z.string()),
  serverTime: z.number().int(),
});
export const SyncResult = z.object({
  opId: z.string(),
  status: z.enum(['applied', 'duplicate', 'rejected']),
  error: z.string().optional(),
});
export const SyncResponse = z.object({ results: z.array(SyncResult), snapshot: Snapshot });
export const HistoryQuery = z.object({ limit: z.coerce.number().int().min(1).max(100).default(50), before: z.coerce.number().int().optional() });
export const HistoryResponse = z.object({
  items: z.array(ProgressEntry.extend({ completions: z.number().int() })),
  nextBefore: z.number().int().nullable(),
});

// ---------------------------------------------------------------- levels

export const Difficulty = z.enum(['beginner', 'easy', 'medium', 'hard', 'expert']);
export const TileSchema = z.object({
  t: z.enum(['empty', 'blocked', 'straight', 'corner', 'tee', 'cross', 'source', 'dest']),
  r: z.number().int().min(0).max(3),
  l: z.boolean().optional(),
  c: z.number().int().min(0).max(3).optional(),
  n: z.number().int().min(1).max(9).optional(),
});
export const LevelSchema = z.object({
  id: z.string(),
  name: z.string(),
  version: z.number().int(),
  difficulty: Difficulty,
  difficultyScore: z.number().int(),
  width: z.number().int(),
  height: z.number().int(),
  tiles: z.array(TileSchema),
  generator: GeneratorRef.nullable(),
  par: z.number().int(),
  tip: z.string().optional(),
  solution: z.object({ rotations: z.array(z.number().int()), moves: MovesSchema }).optional(),
  solutionCount: z.number().int().optional(),
  solutionCountCapped: z.boolean().optional(),
});
export const LevelSummary = z.object({ id: z.string(), name: z.string(), difficulty: Difficulty, par: z.number().int(), packId: z.string().nullable(), ordinal: z.number().int(), contentVersion: z.number().int() });
export const LevelsQuery = z.object({ pack: z.string().max(32).optional(), difficulty: Difficulty.optional(), limit: z.coerce.number().int().min(1).max(100).default(50), cursor: z.string().max(64).optional() });
export const LevelsResponse = z.object({ levels: z.array(LevelSummary), nextCursor: z.string().nullable() });
export const PacksResponse = z.object({ packs: z.array(z.object({ id: z.string(), name: z.string(), description: z.string(), levelIds: z.array(z.string()) })) });

// ---------------------------------------------------------------- daily & leaderboards

export const DailyQuery = z.object({ date: IsoDate.optional() });
export const DailyResponse = z.object({ date: IsoDate, tier: Difficulty, generatorVersion: z.string(), level: LevelSchema, par: z.number().int(), closesAt: z.string() });
export const DailySubmitRequest = z.object({ date: IsoDate, moves: MovesSchema, submissionId: z.string().min(8).max(64) }).strict();
export const DailySubmitResponse = z.object({
  valid: z.boolean(),
  rotations: z.number().int(),
  best: z.number().int().nullable(),
  rank: z.number().int().nullable(),
  error: z.string().nullable(),
  duplicate: z.boolean(),
});
export const LeaderboardQuery = z.object({ date: IsoDate.optional(), week: z.string().regex(/^\d{4}-W\d{2}$/).optional(), limit: z.coerce.number().int().min(1).max(100).default(20) });
export const LeaderboardEntry = z.object({ rank: z.number().int(), displayName: z.string(), score: z.number().int(), rotations: z.number().int(), solved: z.number().int().optional(), isMe: z.boolean() });
export const LeaderboardResponse = z.object({ board: z.string(), entries: z.array(LeaderboardEntry), me: LeaderboardEntry.nullable() });

// ---------------------------------------------------------------- friend challenges

/** How the server rebuilds the exact puzzle: a campaign level, an official daily, or generator parameters. */
export const ChallengeLevelRef = z.discriminatedUnion('type', [
  z.object({ type: z.literal('campaign'), levelId: z.string().max(64) }).strict(),
  z.object({ type: z.literal('daily'), date: IsoDate }).strict(),
  z.object({ type: z.literal('generated'), seed: z.number().int().min(0).max(0xffffffff), tier: Difficulty, version: z.string().max(16) }).strict(),
]);
export const ChallengeCode = z.string().regex(/^[A-HJ-NP-Z2-9]{8}$/, 'Invalid challenge code');
export const FriendChallengeCreateRequest = z.object({ level: ChallengeLevelRef, moves: MovesSchema }).strict();
export const FriendChallengeCreateResponse = z.object({ code: ChallengeCode, url: z.string(), rotations: z.number().int(), expiresAt: z.string() });
export const FriendChallengeView = z.object({
  code: ChallengeCode,
  level: LevelSchema,
  creatorName: z.string(),
  creatorRotations: z.number().int(),
  attempts: z.number().int(),
  createdAt: z.string(),
  expiresAt: z.string(),
});
export const FriendAttemptRequest = z.object({ moves: MovesSchema }).strict();
export const FriendAttemptResponse = z.object({
  valid: z.boolean(),
  rotations: z.number().int(),
  best: z.number().int().nullable(),
  creatorRotations: z.number().int(),
  outcome: z.enum(['win', 'tie', 'lose']).nullable(),
  error: z.string().nullable(),
});
export const FriendResultsResponse = z.object({
  code: ChallengeCode,
  creatorName: z.string(),
  creatorRotations: z.number().int(),
  entries: z.array(z.object({ rank: z.number().int(), displayName: z.string(), rotations: z.number().int(), isMe: z.boolean(), isCreator: z.boolean() })),
});

// ---------------------------------------------------------------- achievements, config, privacy, purchases

export const AchievementDef = z.object({ id: z.string(), title: z.string(), description: z.string(), metric: z.string(), threshold: z.number().int() });
export const AchievementsResponse = z.object({ achievements: z.array(AchievementDef) });
export const MyAchievementsResponse = z.object({ achievements: z.array(z.object({ id: z.string(), unlockedAt: z.string() })) });
export const ConfigResponse = z.object({ version: z.number().int(), config: z.record(z.unknown()) });
export const DeleteRequest = z.object({ confirm: z.literal(true) }).strict();
export const DeleteResponse = z.object({ requestId: Uuid, status: z.literal('completed') });
export const PurchaseVerifyRequest = z.object({ store: z.enum(['google_play', 'app_store', 'dev']), productId: z.string().max(64), purchaseToken: z.string().min(1).max(4096) }).strict();
export const EntitlementsResponse = z.object({ entitlements: z.array(z.object({ productId: z.string(), store: z.string(), status: z.string(), verifiedAt: z.string() })) });

export type TSyncOperation = z.infer<typeof SyncOperation>;
export type TSnapshot = z.infer<typeof Snapshot>;
