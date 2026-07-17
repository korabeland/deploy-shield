import { HealthResponseSchema, type HealthResponse } from '@deploy-shield/contracts';

/**
 * Handles GET /api/health. Takes the standard Web `Request` and returns a
 * standard Web `Response` so it can run as a Vercel Edge Function with no
 * extra runtime dependency, and be called directly in tests with no
 * server needed.
 */
export function handleHealth(_request: Request): Response {
  const body: HealthResponse = {
    status: 'ok',
    service: 'example-service',
    timestamp: new Date().toISOString(),
  };

  // Validate against the contract before responding, so the handler and the
  // schema it claims to satisfy can never silently drift apart.
  HealthResponseSchema.parse(body);

  return new Response(JSON.stringify(body), {
    status: 200,
    headers: { 'content-type': 'application/json' },
  });
}
