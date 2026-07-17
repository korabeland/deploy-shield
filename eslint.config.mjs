import { defineConfig, globalIgnores } from 'eslint/config';
import tseslint from 'typescript-eslint';

// Complexity limits are tuned against the real code in packages/contracts
// and services/example-service, with headroom, not picked in the abstract.
// This is a template for AI-generated code, so the bar is strict but not
// performative: a function that trips these limits should be split, not
// have the limit raised to fit it.
const complexityRules = {
  complexity: ['error', 10],
  'max-depth': ['error', 3],
  'max-lines-per-function': [
    'error',
    { max: 60, skipBlankLines: true, skipComments: true },
  ],
  'max-params': ['error', 4],
  'max-lines': [
    'error',
    { max: 300, skipBlankLines: true, skipComments: true },
  ],
};

export default defineConfig([
  globalIgnores([
    '**/node_modules/**',
    '**/coverage/**',
    '**/dist/**',
    '**/.vercel/**',
    '**/reports/**',
    'pnpm-lock.yaml',
  ]),
  {
    files: ['**/*.ts'],
    extends: [
      ...tseslint.configs.strictTypeChecked,
      ...tseslint.configs.stylisticTypeChecked,
    ],
    languageOptions: {
      parserOptions: {
        // Root-level TS files (e.g. vitest.config.ts) aren't included by
        // any workspace tsconfig's `include`; without this they'd fall
        // into projectService's "no project found" error instead of its
        // permissive default project.
        projectService: { allowDefaultProject: ['vitest.config.ts'] },
        tsconfigRootDir: import.meta.dirname,
      },
    },
    rules: {
      ...complexityRules,
      // Matches the codebase's existing `_request`-style convention for
      // intentionally-unused parameters (see services/example-service).
      '@typescript-eslint/no-unused-vars': [
        'error',
        { argsIgnorePattern: '^_', varsIgnorePattern: '^_' },
      ],
    },
  },
  {
    // Typed linting fights vitest idioms (loosely typed mocks, `expect`
    // chains over `unknown`-ish return values) more than it earns its
    // keep in test files. Keep the type-aware rules that catch real bugs;
    // relax the ones that mostly complain about test-double shapes.
    files: ['**/*.test.ts'],
    rules: {
      '@typescript-eslint/no-unsafe-assignment': 'off',
      '@typescript-eslint/no-unsafe-member-access': 'off',
      '@typescript-eslint/no-unsafe-call': 'off',
      'max-lines-per-function': 'off',
    },
  },
  {
    // Config/script files: plain ESM, no type-aware rules — they aren't
    // part of any tsconfig's `include`, so `projectService` can't (and
    // shouldn't) resolve them.
    files: ['**/*.mjs'],
    languageOptions: {
      ecmaVersion: 'latest',
      sourceType: 'module',
    },
  },
]);
