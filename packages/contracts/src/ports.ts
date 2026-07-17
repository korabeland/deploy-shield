import type { EchoRequest, EchoResponse, HealthResponse } from './types.js';

/**
 * Port a service implements to report its own health. Kept async so
 * real implementations can check dependencies (DB, downstream services)
 * without changing the contract.
 */
export interface HealthPort {
  check(): Promise<HealthResponse>;
}

/**
 * Port a service implements to handle an echo request.
 */
export interface EchoPort {
  echo(request: EchoRequest): Promise<EchoResponse>;
}
