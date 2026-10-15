# Loop Factory — API

Node 22 · TypeScript · Express 4 · Zod · Prisma 6 · PostgreSQL 16 · pino.

```bash
npm run dev -w @loopfactory/api          # watch mode (needs env vars, see ../../.env.example)
npm test -w @loopfactory/api             # integration tests against TEST_DATABASE_URL
npm run build -w @loopfactory/api        # esbuild bundle -> dist/
npm run openapi -w @loopfactory/api      # regenerate docs/api/openapi.json
```

## Source map

| Path | Purpose |
|---|---|
| `src/routes/index.ts` | **Every endpoint**, declared once with its schemas (validation + OpenAPI) |
| `src/http.ts` | Route registry and mounting |
| `src/openapi.ts` | OpenAPI 3.1 builder |
| `src/services/` | tokens, identity, progress (sync), daily, leaderboards, achievements, privacy, purchases, monitoring |
| `src/middleware/` | auth (bearer JWT), rate limiting |
| `src/config.ts` | env parsing; refuses unsafe production config |
| `src/server.ts` | HTTP server, optional cluster mode (`WEB_CONCURRENCY`), graceful shutdown |
| `src/scripts/` | seed, maintenance (retention), daily pre-generation, OpenAPI writer |
| `test/` | supertest integration suites |

Docs: [API overview](../../docs/api.md) · [sync rules](../../docs/sync.md) ·
[security](../../docs/security.md) · [deployment](../../docs/deployment.md).
