/**
 * Data-retention job (run daily):
 *  - refresh tokens: delete expired or revoked/rotated older than 30 days
 *  - sync_operations: keep 90 days (idempotency window is far shorter in practice)
 *  - invalid challenge submissions: keep 30 days (abuse investigation)
 *  - privacy_requests: keep 3 years (proof of erasure; contains only a salted hash)
 */
import { loadConfig } from '../config';
import { createDb } from '../db';

const db = createDb(loadConfig().databaseUrl);
const daysAgo = (n: number) => new Date(Date.now() - n * 86400_000);
const tokens = await db.refreshToken.deleteMany({ where: { OR: [{ expiresAt: { lt: new Date() } }, { revokedAt: { lt: daysAgo(30) } }, { rotatedAt: { lt: daysAgo(30) } }] } });
const ops = await db.syncOperation.deleteMany({ where: { receivedAt: { lt: daysAgo(90) } } });
const subs = await db.challengeSubmission.deleteMany({ where: { valid: false, createdAt: { lt: daysAgo(30) } } });
const priv = await db.privacyRequest.deleteMany({ where: { createdAt: { lt: daysAgo(3 * 365) } } });
console.log(JSON.stringify({ refreshTokens: tokens.count, syncOperations: ops.count, invalidSubmissions: subs.count, privacyRequests: priv.count }));
await db.$disconnect();
