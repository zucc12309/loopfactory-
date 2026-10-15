# syntax=docker/dockerfile:1.7
# Loop Factory API — multi-stage build. Build context: repository root.
#   docker build -f infrastructure/docker/api.Dockerfile -t loopfactory-api .
# Build args:
#   NODE_IMAGE       base image (override to use a registry mirror)
#   INSTALL_OPENSSL  install libssl via apt (required by Prisma engines on *-slim images);
#                    set to false when NODE_IMAGE already ships OpenSSL (e.g. node:22-bookworm)
ARG NODE_IMAGE=node:22-bookworm-slim

FROM ${NODE_IMAGE} AS base
ARG INSTALL_OPENSSL=true
RUN if [ "$INSTALL_OPENSSL" = "true" ]; then \
      apt-get update && apt-get install -y --no-install-recommends openssl ca-certificates && rm -rf /var/lib/apt/lists/*; \
    fi
WORKDIR /app

FROM base AS deps
COPY package.json package-lock.json ./
COPY packages/engine/package.json packages/engine/
COPY packages/contracts/package.json packages/contracts/
COPY services/api/package.json services/api/
RUN npm ci --workspaces --include-workspace-root --ignore-scripts

FROM deps AS build
COPY tsconfig.base.json ./
COPY packages packages
COPY services/api services/api
COPY database database
RUN npx prisma generate --schema database/schema.prisma \
 && npm run build -w @loopfactory/api

FROM base AS runtime
ENV NODE_ENV=production
COPY package.json package-lock.json ./
COPY packages/engine/package.json packages/engine/
COPY packages/contracts/package.json packages/contracts/
COPY services/api/package.json services/api/
# Production deps only; then let Prisma fetch the engines for this platform at build time
# (never at runtime — the container runs as an unprivileged user with a read-only app dir).
RUN npm ci --workspaces --include-workspace-root --omit=dev --ignore-scripts \
 && npx prisma version >/dev/null \
 && npm cache clean --force
COPY --from=build /app/node_modules/.prisma node_modules/.prisma
COPY --from=build /app/services/api/dist services/api/dist
COPY database database
USER node
EXPOSE 8080
HEALTHCHECK --interval=15s --timeout=3s --start-period=20s CMD node -e "fetch('http://127.0.0.1:'+(process.env.PORT||8080)+'/health').then(r=>process.exit(r.ok?0:1)).catch(()=>process.exit(1))"
# server.ts handles SIGTERM/SIGINT itself (graceful shutdown), so no init shim is required.
# Migrations run as a separate release step:  node_modules/.bin/prisma migrate deploy --schema database/schema.prisma
CMD ["node", "services/api/dist/server.js"]
