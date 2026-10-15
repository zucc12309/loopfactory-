import { PrismaClient } from '@prisma/client';

export function createDb(url: string, poolSize?: number) {
  const u = new URL(url);
  if (poolSize && !u.searchParams.has('connection_limit')) u.searchParams.set('connection_limit', String(poolSize));
  return new PrismaClient({ datasources: { db: { url: u.toString() } }, log: ['warn'] });
}
export type Db = PrismaClient;

/** Postgres unique-violation detection for Prisma errors. */
export function isUniqueViolation(e: unknown): boolean {
  return typeof e === 'object' && e !== null && (e as { code?: string }).code === 'P2002';
}
