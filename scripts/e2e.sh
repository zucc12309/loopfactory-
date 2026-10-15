#!/usr/bin/env bash
# End-to-end: starts the API on a scratch port against the test database, then runs the real Godot
# client autoloads through offline play, reconnection, sync, a daily submission and a friend challenge.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PORT="${E2E_PORT:-8787}"
export NODE_ENV=test PORT DATABASE_URL="${TEST_DATABASE_URL:-postgresql://loop:loop@localhost:5432/loopfactory_test}"
export JWT_SECRET=e2e-secret-e2e-secret-e2e-secret-e2e DAILY_SEED_SECRET=e2e-daily-seed-secret PRIVACY_HASH_SALT=e2e-privacy-salt-123 LOG_LEVEL=warn RATE_LIMIT_DISABLED=true ENABLE_DEV_AUTH=true
cd "$ROOT/services/api"
npx prisma migrate deploy --schema ../../database/schema.prisma >/dev/null
npx tsx src/scripts/seed.ts
# npx -> tsx -> node: run the server in its own process group and stop the whole group, so no
# listener (or inherited stdout pipe) outlives the test.
setsid npx tsx src/server.ts & PID=$!
trap 'kill -- -$PID 2>/dev/null || true' EXIT
for _ in $(seq 1 40); do curl -sf "http://127.0.0.1:$PORT/ready" >/dev/null && break; sleep 0.5; done
cd "$ROOT/apps/game"
"${GODOT:-godot}" --headless --path . --import >/dev/null 2>&1 || true
LOG=$(mktemp)
set +e
LF_API="http://127.0.0.1:$PORT" timeout 180 "${GODOT:-godot}" --headless --path . -s res://tests_e2e/e2e_sync.gd 2>&1 | tee "$LOG"
STATUS=${PIPESTATUS[0]}
set -e
# Godot exits 0 when a script fails to compile, so a parse error must fail the run explicitly, and a
# run that never reached its summary line is a failure too.
if grep -E "SCRIPT ERROR|Parse Error|Failed to load script" "$LOG" >/dev/null || ! grep -q "^E2E: 0 failure" "$LOG"; then
  echo "::error::E2E did not complete cleanly"
  STATUS=1
fi
rm -f "$LOG"
exit $STATUS
