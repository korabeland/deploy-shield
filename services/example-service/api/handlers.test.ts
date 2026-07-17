import {
  EchoResponseSchema,
  HealthResponseSchema,
} from '@deploy-shield/contracts';
import { describe, expect, it } from 'vitest';

import echoHandler from './echo.js';
import healthHandler from './health.js';

// These tests exercise the Vercel entrypoints themselves (not just the src/
// handlers they wrap) so the changed-file coverage gate sees them as covered.
describe('api entrypoints', () => {
  it('health entrypoint returns a contracts-shaped health response', async () => {
    const response = await healthHandler(
      new Request('http://localhost/api/health'),
    );

    expect(response.status).toBe(200);
    HealthResponseSchema.parse(await response.json());
  });

  it('echo entrypoint delegates to the echo handler', async () => {
    const response = await echoHandler(
      new Request('http://localhost/api/echo', {
        method: 'POST',
        headers: { 'content-type': 'application/json' },
        body: JSON.stringify({ message: 'hello' }),
      }),
    );

    expect(response.status).toBe(200);
    const body = EchoResponseSchema.parse(await response.json());
    expect(body.message).toBe('hello');
  });
});
