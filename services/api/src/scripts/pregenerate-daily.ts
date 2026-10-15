/** Pre-generates the next N daily challenges (run from a scheduled job; generation is also lazy). */
import { loadConfig } from '../config';
import { createDb } from '../db';
import { DailyService } from '../services/daily';

const config = loadConfig();
const db = createDb(config.databaseUrl);
const daily = new DailyService(db, config.dailySeedSecret);
const days = Number(process.argv[2] ?? 3);
for (let k = 0; k < days; k++) {
  const date = new Date(Date.now() + k * 86400_000).toISOString().slice(0, 10);
  const ch = await daily.getOrCreate(date);
  console.log(`${date}: ${ch.tier} par ${ch.par}`);
}
await db.$disconnect();
