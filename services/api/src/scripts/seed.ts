import { loadConfig } from '../config';
import { createDb } from '../db';
import { seed } from '../seed';

const db = createDb(loadConfig().databaseUrl);
const res = await seed(db);
console.log(`Seeded ${res.levels} levels, ${res.achievements} achievements.`);
await db.$disconnect();
