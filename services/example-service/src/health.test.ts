import { HealthResponseSchema } from '@deploy-shield/contracts';
import { describe, expect, it } from 'vitest';
import { handleHealth } from './health.js';

describe('handleHealth', () => {
  it('returns a contracts-typed JSON response for a valid request', async () => {
    const response = await handleHealth(
      new Request('http://localhost/api/health'),
    );

    expect(response.status).toBe(200);
    expect(response.headers.get('content-type')).toBe('application/json');
    const body = HealthResponseSchema.parse(await response.json());
    expect(body.service).toBe('example-service');
    expect(body.status).toBe('ok');
  });
});
