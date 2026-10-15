import { zodToJsonSchema } from 'zod-to-json-schema';
import { ErrorResponse, API_PREFIX } from '@loopfactory/contracts';
import type { AnyRoute } from './http';

const schema = (s: unknown) => zodToJsonSchema(s as Parameters<typeof zodToJsonSchema>[0], { target: 'openApi3', $refStrategy: 'none' });

/** Build an OpenAPI 3.1 document from the route registry (single source of truth). */
export function buildOpenApi(routes: AnyRoute[], version: string) {
  const paths: Record<string, Record<string, unknown>> = {};
  for (const r of routes) {
    const p = API_PREFIX + r.path.replace(/:([a-zA-Z]+)/g, '{$1}');
    paths[p] ??= {};
    const parameters: unknown[] = [];
    for (const [name, description] of Object.entries(r.params ?? {})) parameters.push({ name, in: 'path', required: true, description, schema: { type: 'string' } });
    if (r.query) {
      const q = schema(r.query) as { properties?: Record<string, unknown>; required?: string[] };
      for (const [name, s] of Object.entries(q.properties ?? {})) parameters.push({ name, in: 'query', required: (q.required ?? []).includes(name), schema: s });
    }
    const status = String(r.status ?? (r.response._def?.typeName === 'ZodUndefined' ? 204 : 200));
    const op: Record<string, unknown> = {
      summary: r.summary,
      tags: [r.tag],
      operationId: `${r.method}${r.path.replace(/[/:-](\w)/g, (_m, c: string) => c.toUpperCase())}`,
      parameters,
      responses: {
        [status]: status === '204' ? { description: 'No content' } : { description: 'OK', content: { 'application/json': { schema: schema(r.response) } } },
        '4XX': { description: 'Client error', content: { 'application/json': { schema: schema(ErrorResponse) } } },
        '5XX': { description: 'Server error', content: { 'application/json': { schema: schema(ErrorResponse) } } },
      },
    };
    if (r.auth === 'required') op.security = [{ bearerAuth: [] }];
    if (r.auth === 'optional') op.security = [{}, { bearerAuth: [] }];
    if (r.body) op.requestBody = { required: true, content: { 'application/json': { schema: schema(r.body) } } };
    paths[p][r.method] = op;
  }
  return {
    openapi: '3.1.0',
    info: { title: 'Loop Factory API', version, description: 'REST API for the Loop Factory puzzle game. All competitive scores are derived from server-verified move replays.' },
    servers: [{ url: '/' }],
    components: { securitySchemes: { bearerAuth: { type: 'http', scheme: 'bearer', bearerFormat: 'JWT' } } },
    paths: {
      '/health': { get: { summary: 'Liveness probe', tags: ['ops'], responses: { '200': { description: 'OK' } } } },
      '/ready': { get: { summary: 'Readiness probe (database reachable)', tags: ['ops'], responses: { '200': { description: 'Ready' }, '503': { description: 'Not ready' } } } },
      ...paths,
    },
  };
}
