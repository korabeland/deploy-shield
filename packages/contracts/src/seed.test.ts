import { describe, expect, it } from 'vitest';
import {
  EchoRequestSchema,
  EchoResponseSchema,
  HealthResponseSchema,
} from './schemas.js';
import {
  seedEchoRequest,
  seedEchoResponse,
  seedHealthResponse,
} from './seed.js';

// Seed data is the contract examples downstream services build tests on —
// each seed must actually satisfy its own schema, with the exact documented
// values (not just any parseable shape).
describe('seed data', () => {
  it('seedEchoRequest satisfies EchoRequestSchema with the documented message', () => {
    expect(EchoRequestSchema.parse(seedEchoRequest)).toEqual({
      message: 'hello from deploy shield',
    });
  });

  it('seedEchoResponse satisfies EchoResponseSchema and echoes the seed request', () => {
    const parsed = EchoResponseSchema.parse(seedEchoResponse);

    expect(parsed.message).toBe(seedEchoRequest.message);
    expect(parsed.echoedAt).toBe('2026-01-01T00:00:00.000Z');
  });

  it('seedHealthResponse satisfies HealthResponseSchema with the documented values', () => {
    expect(HealthResponseSchema.parse(seedHealthResponse)).toEqual({
      status: 'ok',
      service: 'example-service',
      timestamp: '2026-01-01T00:00:00.000Z',
    });
  });
});
