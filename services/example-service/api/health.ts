import { handleHealth } from '../src/health.js';

// Web-standard handler on Vercel's default Node.js runtime: Vercel invokes
// this default export with a standard Web `Request` and expects a standard
// Web `Response` back — no @vercel/node dependency or runtime config needed.

export default function handler(request: Request): Promise<Response> {
  return handleHealth(request);
}
