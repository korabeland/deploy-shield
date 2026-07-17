import { EchoResponseSchema, ErrorResponseSchema } from '@deploy-shield/contracts';
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
  it('returns a contracts-typed response for a valid request', async () => {
    const response = await handleEcho(jsonRequest({ message: 'hello' }));

    expect(response.status).toBe(200);
    const body = EchoResponseSchema.parse(await response.json());
    expect(body.message).toBe('hello');
  });

  it('returns a 4xx with a contracts-shaped error body for an invalid request', async () => {
    const response = await handleEcho(jsonRequest({}));

    expect(response.status).toBe(400);
    const body = ErrorResponseSchema.parse(await response.json());
    expect(body.field).toBe('message');
  });
});
