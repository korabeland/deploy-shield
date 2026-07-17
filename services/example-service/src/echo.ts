import {
  EchoRequestSchema,
  type ErrorResponse,
} from '@deploy-shield/contracts';
import { exampleService } from './service.js';

/**
 * Handles POST /api/echo. Adapts the standard Web `Request`/`Response` pair
 * onto the service's `EchoPort` implementation. Web-standard signature —
 * runs on Vercel's default Node.js runtime with no extra dependency, and
 * can be called directly in tests with no server needed.
 */
export async function handleEcho(request: Request): Promise<Response> {
  let payload: unknown;
  try {
    payload = await request.json();
  } catch {
    return errorResponse('request body must be valid JSON');
  }

  const parsed = EchoRequestSchema.safeParse(payload);
  if (!parsed.success) {
    const firstIssue = parsed.error.issues[0];
    // A non-object body (e.g. a bare string) yields an issue with an empty
    // path — only name a field when the issue actually points at one.
    const field =
      firstIssue && firstIssue.path.length > 0
        ? String(firstIssue.path[0])
        : undefined;
    return errorResponse(firstIssue?.message ?? 'invalid request body', field);
  }

  const body = await exampleService.echo(parsed.data);

  return new Response(JSON.stringify(body), {
    status: 200,
    headers: { 'content-type': 'application/json' },
  });
}

function errorResponse(error: string, field?: string): Response {
  const body: ErrorResponse =
    field === undefined ? { error } : { error, field };

  return new Response(JSON.stringify(body), {
    status: 400,
    headers: { 'content-type': 'application/json' },
  });
}
