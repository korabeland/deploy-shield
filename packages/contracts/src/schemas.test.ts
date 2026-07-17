import { describe, expect, it } from 'vitest';
import { EchoRequestSchema, HealthResponseSchema } from './schemas.js';

describe('EchoRequestSchema', () => {
  it('accepts a valid payload', () => {
    const result = EchoRequestSchema.safeParse({ message: 'hello' });

    expect(result.success).toBe(true);
  });

  it('rejects a payload missing the message field, naming the field', () => {
    const result = EchoRequestSchema.safeParse({});

    expect(result.success).toBe(false);
    if (!result.success) {
      expect(result.error.issues[0]?.path).toEqual(['message']);
    }
  });
});

describe('HealthResponseSchema', () => {
  it('accepts a valid payload', () => {
    const result = HealthResponseSchema.safeParse({
      status: 'ok',
      service: 'example-service',
      timestamp: new Date().toISOString(),
    });

    expect(result.success).toBe(true);
  });

  it('rejects a payload with an unknown status, naming the field', () => {
    const result = HealthResponseSchema.safeParse({
      status: 'unknown',
      service: 'example-service',
      timestamp: new Date().toISOString(),
    });

    expect(result.success).toBe(false);
    if (!result.success) {
      expect(result.error.issues[0]?.path).toEqual(['status']);
    }
  });
});
