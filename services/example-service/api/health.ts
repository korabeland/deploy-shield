import { handleHealth } from '../src/health.js';

// Vercel's Node.js runtime accepts a web-standard handler in exactly two
// shapes: a named HTTP-method export (this one) or `export default { fetch }`.
// A bare `export default function handler(request)` is NOT one of them — it
// lands in the legacy (req, res) slot, so the returned Response is discarded,
// the response is never ended, and every request hangs until the function
// times out at 300s. Naming the method also lets Vercel answer other verbs
// with 405 before this code runs.
export function GET(request: Request): Promise<Response> {
  return handleHealth(request);
}
