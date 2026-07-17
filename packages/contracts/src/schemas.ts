import { z } from 'zod';

/**
 * Request body for the example service's echo endpoint.
 */
export const EchoRequestSchema = z.object({
  message: z.string().min(1, 'message must not be empty'),
});

/**
 * Successful response body for the echo endpoint.
 */
export const EchoResponseSchema = z.object({
  message: z.string(),
  echoedAt: z.string().datetime(),
});

export const HealthStatusSchema = z.enum(['ok', 'degraded']);

/**
 * Successful response body for the health endpoint.
 */
export const HealthResponseSchema = z.object({
  status: HealthStatusSchema,
  service: z.string(),
  timestamp: z.string().datetime(),
});

/**
 * Shared error shape every contracts-typed endpoint returns on a 4xx.
 */
export const ErrorResponseSchema = z.object({
  error: z.string(),
  field: z.string().optional(),
});
