import { HealthResponseSchema } from '@deploy-shield/contracts';
import { exampleService } from './service.js';

/**
 * Handles GET /api/health. Adapts the standard Web `Request`/`Response`
 * pair onto the service's `HealthPort` implementation. Web-standard
 * signature — runs on Vercel's default Node.js runtime with no extra
 * dependency, and can be called directly in tests with no server needed.
 */
export async function handleHealth(_request: Request): Promise<Response> {
  const body = await exampleService.check();

  // Validate against the contract before responding, so the handler and the
  // schema it claims to satisfy can never silently drift apart.
  HealthResponseSchema.parse(body);

  return new Response(JSON.stringify(body), {
    status: 200,
    headers: { 'content-type': 'application/json' },
  });
}
