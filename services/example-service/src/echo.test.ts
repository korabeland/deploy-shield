import {
  EchoResponseSchema,
  ErrorResponseSchema,
} from '@deploy-shield/contracts';
import { describe, expect, it } from 'vitest';
import { handleEcho } from './echo.js';

function jsonRequest(body: unknown): Request {
  return new Request('http://localhost/api/echo', {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify(body),
  });
}

describe('handleEcho', () => {
  it('returns a contracts-typed JSON response for a valid request', async () => {
    const response = await handleEcho(jsonRequest({ message: 'hello' }));

    expect(response.status).toBe(200);
    expect(response.headers.get('content-type')).toBe('application/json');
    const body = EchoResponseSchema.parse(await response.json());
    expect(body.message).toBe('hello');
  });

  it('returns a 4xx naming the failing field and its zod message', async () => {
    const response = await handleEcho(jsonRequest({}));

    expect(response.status).toBe(400);
    expect(response.headers.get('content-type')).toBe('application/json');
    const body = ErrorResponseSchema.parse(await response.json());
    expect(body.field).toBe('message');
    // The error text is the zod issue's own message (exact wording belongs
    // to zod), not the handler's generic fallback.
    expect(body.error).toBeTruthy();
    expect(body.error).not.toBe('invalid request body');
  });

  it('rejects a malformed (non-JSON) body without a field name', async () => {
    const response = await handleEcho(
      new Request('http://localhost/api/echo', {
        method: 'POST',
        headers: { 'content-type': 'application/json' },
        body: 'not json {',
      }),
    );

    expect(response.status).toBe(400);
    // Exact body shape: the documented error text and no `field` key at all.
    expect(await response.json()).toEqual({
      error: 'request body must be valid JSON',
    });
  });
});
