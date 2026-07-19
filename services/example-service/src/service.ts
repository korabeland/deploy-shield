import type {
  EchoPort,
  EchoRequest,
  EchoResponse,
  HealthPort,
  HealthResponse,
} from '@deploy-shield/contracts';

/**
 * Domain implementation of this service's contract ports. The HTTP handlers
 * in this directory are thin adapters over these methods — the ports are the
 * service's actual contract surface, and typing this object as
 * `HealthPort & EchoPort` keeps implementation and contract compiler-checked
 * against each other.
 */
export const exampleService: HealthPort & EchoPort = {
  // The ports are Promise-based so real implementations can check
  // dependencies (DB, downstream services); this example has none, so it
  // resolves synchronously rather than carrying no-op `async`.
  check(): Promise<HealthResponse> {
    return Promise.resolve({
      status: 'ok',
      service: 'example-service',
      timestamp: new Date().toISOString(),
    });
  },

  echo(request: EchoRequest): Promise<EchoResponse> {
    return Promise.resolve({
      message: request.message,
      echoedAt: new Date().toISOString(),
    });
  },
};
