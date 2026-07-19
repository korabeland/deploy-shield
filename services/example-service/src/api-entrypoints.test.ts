import {
  EchoResponseSchema,
  HealthResponseSchema,
} from '@deploy-shield/contracts';
import { describe, expect, it } from 'vitest';

import { POST as echoHandler } from '../api/echo.js';
import { GET as healthHandler } from '../api/health.js';

// These tests exercise the Vercel entrypoints themselves (not just the src/
// handlers they wrap) so the changed-file coverage gate sees them as covered.
//
// They live in src/, NOT next to the entrypoints in api/: Vercel compiles
// every file under api/ into its own serverless function, so a colocated
// *.test.ts ships as a live public endpoint. `.vercelignore` blocks that too;
// this file's location is the first line of defense.
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
