import { defineConfig } from 'vitest/config';

// Project-scoped config for this package. The root vitest.config.ts drives
// `pnpm test` via `test.projects` and is sufficient for that use case, but
// tools that run standalone from inside this package directory (notably
// Stryker's vitest-runner, which has no concept of the root's workspace
// `projects` glob) need a config file they can resolve on their own.
export default defineConfig({
  test: {
    name: 'contracts',
    environment: 'node',
  },
});
