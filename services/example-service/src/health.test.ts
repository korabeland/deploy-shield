import { HealthResponseSchema } from '@deploy-shield/contracts';
import { describe, expect, it } from 'vitest';
import { handleHealth } from './health.js';

describe('handleHealth', () => {
  it('returns a contracts-typed response for a valid request', async () => {
    const response = handleHealth(new Request('http://localhost/api/health'));

    expect(response.status).toBe(200);
    const body = HealthResponseSchema.parse(await response.json());
    expect(body.service).toBe('example-service');
  });
});
