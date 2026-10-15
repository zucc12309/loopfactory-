-- Successor of a rotated refresh token (bounded retry after a lost refresh response).
ALTER TABLE "refresh_tokens" ADD COLUMN "replaced_by_id" UUID;
