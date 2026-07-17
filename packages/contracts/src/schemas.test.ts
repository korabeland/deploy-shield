import { describe, expect, it } from 'vitest';
import {
  EchoRequestSchema,
  EchoResponseSchema,
  ErrorResponseSchema,
  HealthResponseSchema,
  HealthStatusSchema,
} from './schemas.js';

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

  it('rejects an empty message with the documented error message', () => {
    const result = EchoRequestSchema.safeParse({ message: '' });

    expect(result.success).toBe(false);
    if (!result.success) {
      expect(result.error.issues[0]?.message).toBe('message must not be empty');
    }
  });
});

describe('EchoResponseSchema', () => {
  it('requires message and a valid ISO echoedAt timestamp', () => {
    expect(
      EchoResponseSchema.safeParse({
        message: 'hello',
        echoedAt: '2026-01-01T00:00:00.000Z',
      }).success,
    ).toBe(true);
    expect(EchoResponseSchema.safeParse({}).success).toBe(false);
    expect(
      EchoResponseSchema.safeParse({ message: 'hello', echoedAt: 'not-a-date' })
        .success,
    ).toBe(false);
  });
});

describe('HealthStatusSchema', () => {
  it('accepts exactly the documented statuses', () => {
    expect(HealthStatusSchema.safeParse('ok').success).toBe(true);
    expect(HealthStatusSchema.safeParse('degraded').success).toBe(true);
    expect(HealthStatusSchema.safeParse('').success).toBe(false);
    expect(HealthStatusSchema.safeParse('down').success).toBe(false);
  });
});

describe('ErrorResponseSchema', () => {
  it('requires error, allows an optional field name', () => {
    expect(ErrorResponseSchema.safeParse({ error: 'bad input' }).success).toBe(
      true,
    );
    expect(
      ErrorResponseSchema.safeParse({ error: 'bad input', field: 'message' })
        .success,
    ).toBe(true);
    expect(ErrorResponseSchema.safeParse({}).success).toBe(false);
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
