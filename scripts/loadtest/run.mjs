// Load test for the Loop Factory API (autocannon). Usage:
//   node scripts/loadtest/run.mjs http://127.0.0.1:8080 <server-pid> [durationSeconds]
// Scenarios: daily puzzle read spike, authenticated mixed traffic (profile/sync/leaderboard) and a
// daily-submission spike, each at 100 and 1000 concurrent connections. Samples server CPU/RSS
// from /proc and PostgreSQL connections from pg_stat_activity while running.
import autocannon from 'autocannon';
import { execSync } from 'node:child_process';
import { readFileSync, writeFileSync } from 'node:fs';
import { randomUUID } from 'node:crypto';

const [base = 'http://127.0.0.1:8080', pidArg, durArg] = process.argv.slice(2);
const pid = Number(pidArg);
const duration = Number(durArg ?? 20);
const CLK = Number(execSync('getconf CLK_TCK').toString());

// Server process plus any cluster workers (children of the primary).
function serverPids() {
  let kids = [];
  try {
    kids = execSync(`pgrep -P ${pid}`).toString().trim().split('\n').filter(Boolean).map(Number);
  } catch {
    /* no children */
  }
  return [pid, ...kids];
}
function procSample() {
  let cpuTicks = 0;
  let rssKb = 0;
  for (const p of serverPids()) {
    try {
      const stat = readFileSync(`/proc/${p}/stat`, 'utf8').split(') ')[1].split(' ');
      cpuTicks += Number(stat[11]) + Number(stat[12]);
      rssKb += Number(readFileSync(`/proc/${p}/status`, 'utf8').match(/VmRSS:\s+(\d+)/)[1]);
    } catch {
      /* process exited */
    }
  }
  return { cpuTicks, rssKb, t: Date.now() };
}
function dbConnections() {
  try {
    return Number(execSync(`psql "${process.env.LOAD_DB_URL}" -tAc "select count(*) from pg_stat_activity where datname=current_database()"`).toString().trim());
  } catch {
    return -1;
  }
}

async function json(method, path, body, token) {
  const r = await fetch(base + path, { method, headers: { 'content-type': 'application/json', ...(token ? { authorization: `Bearer ${token}` } : {}) }, body: body ? JSON.stringify(body) : undefined });
  return r.json();
}

async function scenario(name, connections, opts) {
  const samples = [];
  let prev = procSample();
  const timer = setInterval(() => {
    const cur = procSample();
    samples.push({ cpu: ((cur.cpuTicks - prev.cpuTicks) / CLK) / ((cur.t - prev.t) / 1000) * 100, rssMb: cur.rssKb / 1024, db: dbConnections() });
    prev = cur;
  }, 1000);
  const res = await autocannon({ url: base, connections, duration, timeout: 20, ...opts });
  clearInterval(timer);
  const non2xx = res.non2xx;
  const out = {
    scenario: name,
    connections,
    durationS: duration,
    requests: res.requests.total,
    rps: Math.round(res.requests.average),
    latencyMs: { p50: res.latency.p50, p90: res.latency.p90, p97_5: res.latency.p97_5, p99: res.latency.p99, max: res.latency.max },
    errors: res.errors + res.timeouts,
    non2xx,
    errorRate: +(((res.errors + res.timeouts + non2xx) / Math.max(1, res.requests.total + res.errors)) * 100).toFixed(3),
    cpuPctAvg: +(samples.reduce((a, s) => a + s.cpu, 0) / Math.max(1, samples.length)).toFixed(1),
    cpuPctMax: +Math.max(...samples.map((s) => s.cpu)).toFixed(1),
    rssMbMax: +Math.max(...samples.map((s) => s.rssMb)).toFixed(1),
    dbConnectionsMax: Math.max(...samples.map((s) => s.db)),
  };
  console.log(JSON.stringify(out));
  return out;
}

// ---- setup: player tokens and today's daily solution
const players = [];
for (let i = 0; i < 300; i++) players.push((await json('POST', '/api/v1/auth/guest', {})).accessToken);
const daily = await json('GET', '/api/v1/challenges/daily');
const { solve } = await import('../../packages/engine/src/index.ts').catch(() => ({}));
let moves = null;
if (solve) moves = solve(daily.level).moves;
else moves = JSON.parse(execSync(`npx tsx -e "import {solve} from './packages/engine/src/index.ts'; const l=${JSON.stringify(JSON.stringify(daily.level))}; console.log(JSON.stringify(solve(JSON.parse(l)).moves))"`).toString());
let k = 0;
const pick = () => players[k++ % players.length];

const results = [];
for (const connections of [100, 1000]) {
  results.push(await scenario('daily_read_spike', connections, { requests: [{ method: 'GET', path: '/api/v1/challenges/daily' }] }));
  results.push(await scenario('authenticated_mix', connections, {
    requests: [
      { method: 'GET', path: '/api/v1/player/me', setupRequest: (r) => ({ ...r, headers: { authorization: `Bearer ${pick()}` } }) },
      {
        method: 'POST', path: '/api/v1/progress/sync',
        setupRequest: (r) => ({ ...r, headers: { authorization: `Bearer ${pick()}`, 'content-type': 'application/json' }, body: JSON.stringify({ operations: [{ opId: randomUUID(), type: 'settings', clientTs: Date.now(), payload: { settings: { sfx: true }, updatedAt: Date.now() } }] }) }),
      },
      { method: 'GET', path: '/api/v1/challenges/daily/leaderboard', setupRequest: (r) => ({ ...r, headers: { authorization: `Bearer ${pick()}` } }) },
    ],
  }));
  results.push(await scenario('daily_submit_spike', connections, {
    requests: [{
      method: 'POST', path: '/api/v1/challenges/daily/submit',
      setupRequest: (r) => ({ ...r, headers: { authorization: `Bearer ${pick()}`, 'content-type': 'application/json' }, body: JSON.stringify({ date: daily.date, moves, submissionId: randomUUID() }) }),
    }],
  }));
}
const file = `scripts/loadtest/results/${new Date().toISOString().replace(/[:.]/g, '-')}.json`;
writeFileSync(file, JSON.stringify({ base, duration, workers: serverPids().length > 1 ? serverPids().length - 1 : 1, results, node: process.version, cpus: (await import('node:os')).cpus().length }, null, 2));
console.log(`saved ${file}`);
