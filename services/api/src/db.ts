import { PrismaClient, type Prisma } from '@prisma/client';

export function createDb(url: string, poolSize?: number) {
  const u = new URL(url);
  if (poolSize && !u.searchParams.has('connection_limit')) u.searchParams.set('connection_limit', String(poolSize));
  return new PrismaClient({ datasources: { db: { url: u.toString() } }, log: ['warn'] });
}
export type Db = PrismaClient;
export type Tx = Prisma.TransactionClient;

/**
 * Postgres unique-violation detection for Prisma errors. With `fields`, only a violation of the
 * unique constraint over exactly those columns matches (so an unrelated constraint is never
 * mistaken for, say, a duplicate submission).
 */
export function isUniqueViolation(e: unknown, fields?: string[]): boolean {
  if (typeof e !== 'object' || e === null || (e as { code?: string }).code !== 'P2002') return false;
  if (!fields) return true;
  const target = (e as { meta?: { target?: unknown } }).meta?.target;
  const want = [...fields].sort().join(',');
  if (Array.isArray(target)) return [...target].map(String).sort().join(',') === want;
  // Some engines report the constraint name, e.g. "challenge_submissions_player_id_submission_id_key".
  if (typeof target === 'string') return fields.every((f) => target.includes(f));
  return false;
}

/** Serialization failures, deadlocks and write conflicts: safe to retry the whole transaction. */
export function isRetryableTxError(e: unknown): boolean {
  const code = (e as { code?: string } | null)?.code;
  if (code === 'P2034') return true;
  const msg = e instanceof Error ? e.message : '';
  return /40001|40P01|could not serialize|deadlock detected/i.test(msg);
}

/**
 * Run `fn` in a transaction that first takes a transaction-scoped advisory lock per key (e.g. a
 * player id). Every read-compare-write on that player's scores runs under the lock, so concurrent
 * requests for the same player apply one after another, each seeing the other's committed rows.
 * Different players never wait for each other. Retries are bounded.
 */
export async function lockedTransaction<T>(db: Db, keys: string[], fn: (tx: Tx) => Promise<T>, attempts = 3): Promise<T> {
  const sorted = [...new Set(keys)].sort(); // fixed order: no lock-order deadlocks
  for (let i = 1; ; i++) {
    try {
      return await db.$transaction(
        async (tx) => {
          for (const k of sorted) await tx.$executeRaw`SELECT pg_advisory_xact_lock(hashtextextended(${k}, 0))`;
          return fn(tx);
        },
        { timeout: 15_000, maxWait: 10_000 },
      );
    } catch (e) {
      if (i >= attempts || !isRetryableTxError(e)) throw e;
      await new Promise((r) => setTimeout(r, 20 * i + Math.random() * 30));
    }
  }
}
