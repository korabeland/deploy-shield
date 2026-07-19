import type { EchoRequest, EchoResponse, HealthResponse } from './types.js';

/**
 * Fixed-value seed data shared by every downstream service's tests, so
 * contract examples live in one place instead of being re-invented per test.
 */
export const seedEchoRequest: EchoRequest = {
  message: 'hello from deploy shield',
};

export const seedEchoResponse: EchoResponse = {
  message: seedEchoRequest.message,
  echoedAt: '2026-01-01T00:00:00.000Z',
};

export const seedHealthResponse: HealthResponse = {
  status: 'ok',
  service: 'example-service',
  timestamp: '2026-01-01T00:00:00.000Z',
};
