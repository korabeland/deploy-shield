import type { z } from 'zod';
import type {
  EchoRequestSchema,
  EchoResponseSchema,
  ErrorResponseSchema,
  HealthResponseSchema,
  HealthStatusSchema,
} from './schemas.js';

export type EchoRequest = z.infer<typeof EchoRequestSchema>;
export type EchoResponse = z.infer<typeof EchoResponseSchema>;
export type HealthStatus = z.infer<typeof HealthStatusSchema>;
export type HealthResponse = z.infer<typeof HealthResponseSchema>;
export type ErrorResponse = z.infer<typeof ErrorResponseSchema>;
