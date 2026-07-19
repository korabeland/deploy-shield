import { fileURLToPath } from 'node:url';

import { defineConfig } from 'vitest/config';

// Project-scoped config for this package. The root vitest.config.ts drives
// `pnpm test` via `test.projects` and is sufficient for that use case, but
// tools that run standalone from inside this package directory (notably
// Stryker's vitest-runner, which has no concept of the root's workspace
// `projects` glob) need a config file they can resolve on their own.
export default defineConfig({
  // Contracts resolves to its built dist/ at runtime (Node can't load raw
  // .ts). Tests point at source instead so the suite never needs a build;
  // the deployed artifact is covered by the deploy workflow's smoke test.
  // Mirror of the `paths` entry in tsconfig.base.json.
  resolve: {
    alias: {
      '@deploy-shield/contracts': fileURLToPath(
        new URL('../../packages/contracts/src/index.ts', import.meta.url),
      ),
    },
  },
  test: {
    name: 'example-service',
    environment: 'node',
  },
});
