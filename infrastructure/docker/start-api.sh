#!/bin/sh
# Single-instance start for hosts without a release step (e.g. Render free plan):
# apply migrations, run the idempotent seed, then hand PID 1 to the server.
# Use it as the container command: /app/infrastructure/docker/start-api.sh
set -e
cd /app
node_modules/.bin/prisma migrate deploy --schema database/schema.prisma
node services/api/dist/scripts/seed.js
exec node services/api/dist/server.js
