import {
  EchoRequestSchema,
  type EchoResponse,
  type ErrorResponse,
} from '@deploy-shield/contracts';

/**
 * Handles POST /api/echo. Takes the standard Web `Request` and returns a
 * standard Web `Response` so it can run as a Vercel Edge Function with no
 * extra runtime dependency, and be called directly in tests with no
 * server needed.
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
    return errorResponse(
      firstIssue?.message ?? 'invalid request body',
      firstIssue ? String(firstIssue.path[0]) : undefined,
    );
  }

  const body: EchoResponse = {
    message: parsed.data.message,
    echoedAt: new Date().toISOString(),
  };

  return new Response(JSON.stringify(body), {
    status: 200,
    headers: { 'content-type': 'application/json' },
  });
}

function errorResponse(error: string, field?: string): Response {
  const body: ErrorResponse = field === undefined ? { error } : { error, field };

  return new Response(JSON.stringify(body), {
    status: 400,
    headers: { 'content-type': 'application/json' },
  });
}
