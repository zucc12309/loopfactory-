-- Friend challenges (additive; no changes to existing tables).
-- CreateTable
CREATE TABLE "friend_challenges" (
    "id" UUID NOT NULL,
    "code" VARCHAR(8) NOT NULL,
    "creator_id" UUID NOT NULL,
    "level_ref" JSONB NOT NULL,
    "level" JSONB NOT NULL,
    "creator_moves" JSONB NOT NULL,
    "creator_rotations" INTEGER NOT NULL,
    "created_at" TIMESTAMPTZ(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "expires_at" TIMESTAMPTZ(3) NOT NULL,

    CONSTRAINT "friend_challenges_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "friend_challenge_attempts" (
    "id" UUID NOT NULL,
    "challenge_id" UUID NOT NULL,
    "player_id" UUID NOT NULL,
    "rotations" INTEGER NOT NULL,
    "moves" JSONB NOT NULL,
    "tries" INTEGER NOT NULL DEFAULT 1,
    "created_at" TIMESTAMPTZ(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMPTZ(3) NOT NULL,

    CONSTRAINT "friend_challenge_attempts_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE UNIQUE INDEX "friend_challenges_code_key" ON "friend_challenges"("code");

-- CreateIndex
CREATE INDEX "friend_challenges_creator_id_created_at_idx" ON "friend_challenges"("creator_id", "created_at");

-- CreateIndex
CREATE INDEX "friend_challenge_attempts_challenge_id_rotations_updated_at_idx" ON "friend_challenge_attempts"("challenge_id", "rotations", "updated_at");

-- CreateIndex
CREATE UNIQUE INDEX "friend_challenge_attempts_challenge_id_player_id_key" ON "friend_challenge_attempts"("challenge_id", "player_id");

-- AddForeignKey
ALTER TABLE "friend_challenges" ADD CONSTRAINT "friend_challenges_creator_id_fkey" FOREIGN KEY ("creator_id") REFERENCES "players"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "friend_challenge_attempts" ADD CONSTRAINT "friend_challenge_attempts_challenge_id_fkey" FOREIGN KEY ("challenge_id") REFERENCES "friend_challenges"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "friend_challenge_attempts" ADD CONSTRAINT "friend_challenge_attempts_player_id_fkey" FOREIGN KEY ("player_id") REFERENCES "players"("id") ON DELETE CASCADE ON UPDATE CASCADE;

