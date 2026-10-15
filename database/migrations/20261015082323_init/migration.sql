-- CreateTable
CREATE TABLE "players" (
    "id" UUID NOT NULL,
    "display_name" VARCHAR(24) NOT NULL,
    "settings" JSONB NOT NULL DEFAULT '{}',
    "settings_client_updated_at" BIGINT NOT NULL DEFAULT 0,
    "created_at" TIMESTAMPTZ(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMPTZ(3) NOT NULL,
    "last_seen_at" TIMESTAMPTZ(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "players_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "player_auth_identities" (
    "id" UUID NOT NULL,
    "player_id" UUID NOT NULL,
    "provider" VARCHAR(16) NOT NULL,
    "subject" VARCHAR(255) NOT NULL,
    "email" VARCHAR(320),
    "created_at" TIMESTAMPTZ(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "player_auth_identities_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "refresh_tokens" (
    "id" UUID NOT NULL,
    "player_id" UUID NOT NULL,
    "family_id" UUID NOT NULL,
    "token_hash" CHAR(64) NOT NULL,
    "expires_at" TIMESTAMPTZ(3) NOT NULL,
    "revoked_at" TIMESTAMPTZ(3),
    "rotated_at" TIMESTAMPTZ(3),
    "created_at" TIMESTAMPTZ(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "refresh_tokens_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "level_packs" (
    "id" VARCHAR(32) NOT NULL,
    "name" VARCHAR(64) NOT NULL,
    "description" TEXT NOT NULL DEFAULT '',
    "ordinal" INTEGER NOT NULL,

    CONSTRAINT "level_packs_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "levels" (
    "id" VARCHAR(64) NOT NULL,
    "pack_id" VARCHAR(32),
    "ordinal" INTEGER NOT NULL DEFAULT 0,
    "name" VARCHAR(64) NOT NULL,
    "content_version" INTEGER NOT NULL,
    "difficulty" VARCHAR(16) NOT NULL,
    "difficulty_score" INTEGER NOT NULL,
    "width" INTEGER NOT NULL,
    "height" INTEGER NOT NULL,
    "par" INTEGER NOT NULL,
    "generator_version" VARCHAR(16),
    "seed" BIGINT,
    "definition" JSONB NOT NULL,
    "created_at" TIMESTAMPTZ(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMPTZ(3) NOT NULL,

    CONSTRAINT "levels_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "player_level_progress" (
    "id" UUID NOT NULL,
    "player_id" UUID NOT NULL,
    "kind" VARCHAR(16) NOT NULL,
    "level_key" VARCHAR(96) NOT NULL,
    "content_version" INTEGER NOT NULL,
    "generator" JSONB,
    "best_rotations" INTEGER NOT NULL,
    "par" INTEGER NOT NULL,
    "verified" BOOLEAN NOT NULL DEFAULT false,
    "completions" INTEGER NOT NULL DEFAULT 1,
    "hints_used" INTEGER NOT NULL DEFAULT 0,
    "first_completed_at" TIMESTAMPTZ(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "last_completed_at" TIMESTAMPTZ(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "client_completed_at" BIGINT,

    CONSTRAINT "player_level_progress_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "active_puzzle_states" (
    "player_id" UUID NOT NULL,
    "kind" VARCHAR(16) NOT NULL,
    "level_key" VARCHAR(96) NOT NULL,
    "state" JSONB NOT NULL,
    "client_updated_at" BIGINT NOT NULL,
    "updated_at" TIMESTAMPTZ(3) NOT NULL,

    CONSTRAINT "active_puzzle_states_pkey" PRIMARY KEY ("player_id")
);

-- CreateTable
CREATE TABLE "daily_challenges" (
    "id" UUID NOT NULL,
    "date" DATE NOT NULL,
    "tier" VARCHAR(16) NOT NULL,
    "seed" BIGINT NOT NULL,
    "generator_version" VARCHAR(16) NOT NULL,
    "level" JSONB NOT NULL,
    "par" INTEGER NOT NULL,
    "created_at" TIMESTAMPTZ(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "daily_challenges_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "challenge_submissions" (
    "id" UUID NOT NULL,
    "challenge_id" UUID NOT NULL,
    "player_id" UUID NOT NULL,
    "submission_id" VARCHAR(64) NOT NULL,
    "moves" JSONB NOT NULL,
    "rotations" INTEGER NOT NULL,
    "valid" BOOLEAN NOT NULL,
    "error" VARCHAR(32),
    "created_at" TIMESTAMPTZ(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "challenge_submissions_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "leaderboard_entries" (
    "id" UUID NOT NULL,
    "board" VARCHAR(32) NOT NULL,
    "player_id" UUID NOT NULL,
    "score" INTEGER NOT NULL,
    "achieved_at" TIMESTAMPTZ(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "display" JSONB NOT NULL DEFAULT '{}',

    CONSTRAINT "leaderboard_entries_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "achievements" (
    "id" VARCHAR(32) NOT NULL,
    "title" VARCHAR(64) NOT NULL,
    "description" TEXT NOT NULL,
    "metric" VARCHAR(16) NOT NULL,
    "threshold" INTEGER NOT NULL,

    CONSTRAINT "achievements_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "player_achievements" (
    "player_id" UUID NOT NULL,
    "achievement_id" VARCHAR(32) NOT NULL,
    "unlocked_at" TIMESTAMPTZ(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "player_achievements_pkey" PRIMARY KEY ("player_id","achievement_id")
);

-- CreateTable
CREATE TABLE "sync_operations" (
    "id" UUID NOT NULL,
    "player_id" UUID NOT NULL,
    "op_id" VARCHAR(64) NOT NULL,
    "type" VARCHAR(32) NOT NULL,
    "status" VARCHAR(16) NOT NULL,
    "result" JSONB NOT NULL DEFAULT '{}',
    "client_ts" BIGINT NOT NULL,
    "received_at" TIMESTAMPTZ(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "sync_operations_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "remote_config_versions" (
    "id" SERIAL NOT NULL,
    "version" INTEGER NOT NULL,
    "config" JSONB NOT NULL,
    "active" BOOLEAN NOT NULL DEFAULT false,
    "note" TEXT NOT NULL DEFAULT '',
    "created_at" TIMESTAMPTZ(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "remote_config_versions_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "purchase_entitlements" (
    "id" UUID NOT NULL,
    "player_id" UUID NOT NULL,
    "store" VARCHAR(16) NOT NULL,
    "product_id" VARCHAR(64) NOT NULL,
    "transaction_id" VARCHAR(128) NOT NULL,
    "status" VARCHAR(16) NOT NULL,
    "verified_at" TIMESTAMPTZ(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "revoked_at" TIMESTAMPTZ(3),

    CONSTRAINT "purchase_entitlements_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "privacy_requests" (
    "id" UUID NOT NULL,
    "subject_hash" CHAR(64) NOT NULL,
    "type" VARCHAR(16) NOT NULL,
    "status" VARCHAR(16) NOT NULL,
    "created_at" TIMESTAMPTZ(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "completed_at" TIMESTAMPTZ(3),

    CONSTRAINT "privacy_requests_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE INDEX "player_auth_identities_player_id_idx" ON "player_auth_identities"("player_id");

-- CreateIndex
CREATE UNIQUE INDEX "player_auth_identities_provider_subject_key" ON "player_auth_identities"("provider", "subject");

-- CreateIndex
CREATE UNIQUE INDEX "refresh_tokens_token_hash_key" ON "refresh_tokens"("token_hash");

-- CreateIndex
CREATE INDEX "refresh_tokens_player_id_idx" ON "refresh_tokens"("player_id");

-- CreateIndex
CREATE INDEX "refresh_tokens_family_id_idx" ON "refresh_tokens"("family_id");

-- CreateIndex
CREATE INDEX "refresh_tokens_expires_at_idx" ON "refresh_tokens"("expires_at");

-- CreateIndex
CREATE INDEX "levels_pack_id_ordinal_idx" ON "levels"("pack_id", "ordinal");

-- CreateIndex
CREATE INDEX "levels_difficulty_idx" ON "levels"("difficulty");

-- CreateIndex
CREATE INDEX "player_level_progress_player_id_last_completed_at_idx" ON "player_level_progress"("player_id", "last_completed_at");

-- CreateIndex
CREATE UNIQUE INDEX "player_level_progress_player_id_kind_level_key_key" ON "player_level_progress"("player_id", "kind", "level_key");

-- CreateIndex
CREATE UNIQUE INDEX "daily_challenges_date_key" ON "daily_challenges"("date");

-- CreateIndex
CREATE INDEX "challenge_submissions_challenge_id_valid_rotations_created__idx" ON "challenge_submissions"("challenge_id", "valid", "rotations", "created_at");

-- CreateIndex
CREATE UNIQUE INDEX "challenge_submissions_player_id_submission_id_key" ON "challenge_submissions"("player_id", "submission_id");

-- CreateIndex
CREATE INDEX "leaderboard_entries_board_score_achieved_at_idx" ON "leaderboard_entries"("board", "score", "achieved_at");

-- CreateIndex
CREATE UNIQUE INDEX "leaderboard_entries_board_player_id_key" ON "leaderboard_entries"("board", "player_id");

-- CreateIndex
CREATE INDEX "sync_operations_received_at_idx" ON "sync_operations"("received_at");

-- CreateIndex
CREATE UNIQUE INDEX "sync_operations_player_id_op_id_key" ON "sync_operations"("player_id", "op_id");

-- CreateIndex
CREATE UNIQUE INDEX "remote_config_versions_version_key" ON "remote_config_versions"("version");

-- CreateIndex
CREATE INDEX "remote_config_versions_active_idx" ON "remote_config_versions"("active");

-- CreateIndex
CREATE INDEX "purchase_entitlements_player_id_idx" ON "purchase_entitlements"("player_id");

-- CreateIndex
CREATE UNIQUE INDEX "purchase_entitlements_store_transaction_id_key" ON "purchase_entitlements"("store", "transaction_id");

-- CreateIndex
CREATE INDEX "privacy_requests_subject_hash_idx" ON "privacy_requests"("subject_hash");

-- AddForeignKey
ALTER TABLE "player_auth_identities" ADD CONSTRAINT "player_auth_identities_player_id_fkey" FOREIGN KEY ("player_id") REFERENCES "players"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "refresh_tokens" ADD CONSTRAINT "refresh_tokens_player_id_fkey" FOREIGN KEY ("player_id") REFERENCES "players"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "levels" ADD CONSTRAINT "levels_pack_id_fkey" FOREIGN KEY ("pack_id") REFERENCES "level_packs"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "player_level_progress" ADD CONSTRAINT "player_level_progress_player_id_fkey" FOREIGN KEY ("player_id") REFERENCES "players"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "active_puzzle_states" ADD CONSTRAINT "active_puzzle_states_player_id_fkey" FOREIGN KEY ("player_id") REFERENCES "players"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "challenge_submissions" ADD CONSTRAINT "challenge_submissions_challenge_id_fkey" FOREIGN KEY ("challenge_id") REFERENCES "daily_challenges"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "challenge_submissions" ADD CONSTRAINT "challenge_submissions_player_id_fkey" FOREIGN KEY ("player_id") REFERENCES "players"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "leaderboard_entries" ADD CONSTRAINT "leaderboard_entries_player_id_fkey" FOREIGN KEY ("player_id") REFERENCES "players"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "player_achievements" ADD CONSTRAINT "player_achievements_player_id_fkey" FOREIGN KEY ("player_id") REFERENCES "players"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "player_achievements" ADD CONSTRAINT "player_achievements_achievement_id_fkey" FOREIGN KEY ("achievement_id") REFERENCES "achievements"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "sync_operations" ADD CONSTRAINT "sync_operations_player_id_fkey" FOREIGN KEY ("player_id") REFERENCES "players"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "purchase_entitlements" ADD CONSTRAINT "purchase_entitlements_player_id_fkey" FOREIGN KEY ("player_id") REFERENCES "players"("id") ON DELETE CASCADE ON UPDATE CASCADE;
