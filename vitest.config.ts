import { coverageConfigDefaults, defineConfig } from 'vitest/config';

export default defineConfig({
  test: {
    projects: [
      'packages/*',
      'services/*',
      {
        test: {
          name: 'scripts',
          include: ['scripts/**/*.test.mjs'],
          environment: 'node',
        },
      },
    ],
    coverage: {
      provider: 'v8',
      reporter: ['text', 'json'],
      // Vitest 4 dropped `coverage.all` — files not matched by `include`
      // are invisible to the coverage report entirely, and the changed-file
      // coverage gate (U4) treats a missing file as 0% covered. These globs
      // are load-bearing: keep them in sync with every workspace's source
      // layout.
      include: [
        'packages/*/src/**/*.ts',
        'services/*/src/**/*.ts',
        'services/*/api/**/*.ts',
      ],
      exclude: [...coverageConfigDefaults.exclude, '**/*.test.ts'],
    },
  },
});
