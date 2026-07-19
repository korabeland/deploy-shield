import { handleEcho } from '../src/echo.js';

// Named HTTP-method export, not a bare default export — see api/health.ts for
// why the default-function shape hangs on Vercel's Node.js runtime.
export function POST(request: Request): Promise<Response> {
  return handleEcho(request);
}
