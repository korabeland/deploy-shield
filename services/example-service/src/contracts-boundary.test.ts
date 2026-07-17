import {
  EchoRequestSchema,
  EchoResponseSchema,
  seedEchoRequest,
} from '@deploy-shield/contracts';
import { describe, expect, it } from 'vitest';
import { handleEcho } from './echo.js';

/**
 * Integration check: everything this service knows about the shape of its
 * data comes from the `@deploy-shield/contracts` workspace package, never a
 * relative path into packages/contracts/src. Importing the handler here
 * transitively exercises the workspace link the dependency-cruiser rules
 * (added in U3) assume exists.
 */
describe('example-service <-> @deploy-shield/contracts boundary', () => {
  it('uses contracts seed data end to end through the service handler', async () => {
    expect(EchoRequestSchema.safeParse(seedEchoRequest).success).toBe(true);

    const response = await handleEcho(
      new Request('http://localhost/api/echo', {
        method: 'POST',
        headers: { 'content-type': 'application/json' },
        body: JSON.stringify(seedEchoRequest),
      }),
    );

    expect(response.status).toBe(200);
    const body = EchoResponseSchema.parse(await response.json());
    expect(body.message).toBe(seedEchoRequest.message);
  });
});
