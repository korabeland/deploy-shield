#!/usr/bin/env node
/**
 * Changed-file coverage gate.
 *
 * Fails (exit 1) when any changed source file has file-level statement
 * coverage below `deployShield.changedFileCoverage` (root package.json).
 *
 * This script does NOT run Vitest itself — it assumes
 * `coverage/coverage-final.json` (Istanbul format, from @vitest/coverage-v8)
 * already exists. The hook/CI chain `pnpm vitest run --coverage` before
 * invoking this script.
 *
 * Base-resolution chain (in this exact order — without it the gate passes
 * vacuously in repos with no remote, since merge-base with a local default
 * branch is HEAD, giving an empty diff):
 *   1. env `CHANGED_COVERAGE_BASE`, if explicitly set — CI passes the PR
 *      base SHA or `github.event.before` here. The all-zeros SHA (what
 *      `github.event.before` holds on branch creation / force push) counts
 *      as unset and falls through to the next tier.
 *   2. `git merge-base origin/<default-branch> HEAD`, when a local
 *      `origin` remote exists. The default branch is read from local refs
 *      only (`refs/remotes/origin/HEAD`, falling back to a local
 *      `refs/remotes/origin/main` or `refs/remotes/origin/master` ref) —
 *      never over the network.
 *   3. `HEAD~1`, when it exists.
 *   4. The git empty-tree hash (root-commit case), so a diff can always be
 *      computed even in a brand-new repo.
 */

import { execFileSync } from 'node:child_process';
import { existsSync, readFileSync } from 'node:fs';
import path from 'node:path';
import { pathToFileURL } from 'node:url';

const EMPTY_TREE_HASH = '4b825dc642cb6eb9a060e54bf8d69288fbee4904';

/**
 * Environment for git subprocesses: the real environment (PATH, etc.) with
 * every GIT_* variable stripped, so `cwd` alone decides which repository
 * git acts on. A git hook (pre-push, pre-commit, …) exports GIT_DIR,
 * GIT_WORK_TREE, and GIT_INDEX_FILE into the processes it spawns; left in
 * place, those override `cwd` and silently redirect every command at the
 * hook's repository instead of the one the caller asked for. This gate — and
 * its tests, which point `cwd` at throwaway repos — must always act on `cwd`.
 * Exported so the test suite reuses the exact same sanitization.
 */
export const GIT_ENV = (() => {
  const env = { ...process.env };
  for (const key of Object.keys(env)) {
    if (key.startsWith('GIT_')) {
      delete env[key];
    }
  }
  return env;
})();

// Mirrors vitest.config.ts's `coverage.include` / `coverage.exclude` —
// keep these globs in sync with that file.
const INCLUDE_GLOBS = [
  'packages/*/src/**/*.ts',
  'services/*/src/**/*.ts',
  'services/*/api/**/*.ts',
];
const EXCLUDE_GLOBS = ['**/*.test.ts'];

/**
 * Converts a minimal glob (`*`, `**`) into a RegExp matching POSIX-style
 * relative paths, as produced by `git diff --name-only`.
 */
function globToRegExp(glob) {
  const segments = glob.split('/').map((segment) => {
    if (segment === '**') {
      return '**';
    }
    const escaped = segment.replace(/[.+^${}()|[\]\\]/g, '\\$&');
    return escaped.replace(/\*/g, '[^/]*');
  });
  let pattern = segments.join('/');
  pattern = pattern.replace(/\/\*\*\//g, '/(?:.*/)?');
  pattern = pattern.replace(/^\*\*\//, '(?:.*/)?');
  pattern = pattern.replace(/\/\*\*$/, '/.*');
  return new RegExp(`^${pattern}$`);
}

const INCLUDE_PATTERNS = INCLUDE_GLOBS.map(globToRegExp);
const EXCLUDE_PATTERNS = EXCLUDE_GLOBS.map(globToRegExp);

function isTrackedSourceFile(relativePath) {
  if (EXCLUDE_PATTERNS.some((pattern) => pattern.test(relativePath))) {
    return false;
  }
  return INCLUDE_PATTERNS.some((pattern) => pattern.test(relativePath));
}

/** Runs a git command, returning trimmed stdout or `null` on failure. */
function gitCapture(args, cwd) {
  try {
    return execFileSync('git', args, {
      cwd,
      encoding: 'utf8',
      stdio: ['ignore', 'pipe', 'ignore'],
      env: GIT_ENV,
    }).trim();
  } catch {
    return null;
  }
}

/** Runs a git command purely for its exit code (e.g. `show-ref --quiet`). */
function gitOk(args, cwd) {
  try {
    execFileSync('git', args, { cwd, stdio: 'ignore', env: GIT_ENV });
    return true;
  } catch {
    return false;
  }
}

function resolveOriginDefaultBranch(cwd) {
  const symref = gitCapture(
    ['symbolic-ref', '--short', 'refs/remotes/origin/HEAD'],
    cwd,
  );
  if (symref) {
    return symref.replace(/^origin\//, '');
  }
  for (const candidate of ['main', 'master']) {
    if (
      gitOk(
        ['show-ref', '--verify', '--quiet', `refs/remotes/origin/${candidate}`],
        cwd,
      )
    ) {
      return candidate;
    }
  }
  return null;
}

/** Implements the base-resolution chain documented above. */
function resolveBase({ cwd, env }) {
  if (env.CHANGED_COVERAGE_BASE && !/^0{40}$/.test(env.CHANGED_COVERAGE_BASE)) {
    return {
      base: env.CHANGED_COVERAGE_BASE,
      source: 'env CHANGED_COVERAGE_BASE',
    };
  }

  const remotes = gitCapture(['remote'], cwd);
  if (remotes && remotes.split('\n').includes('origin')) {
    const defaultBranch = resolveOriginDefaultBranch(cwd);
    if (defaultBranch) {
      const mergeBase = gitCapture(
        ['merge-base', `origin/${defaultBranch}`, 'HEAD'],
        cwd,
      );
      if (mergeBase) {
        return {
          base: mergeBase,
          source: `merge-base with origin/${defaultBranch}`,
        };
      }
    }
  }

  const headParent = gitCapture(['rev-parse', '--verify', 'HEAD~1'], cwd);
  if (headParent) {
    return { base: headParent, source: 'HEAD~1' };
  }

  return { base: EMPTY_TREE_HASH, source: 'empty tree (root commit)' };
}

function listChangedSourceFiles({ cwd, env }) {
  const { base, source } = resolveBase({ cwd, env });
  const diffOutput = gitCapture(['diff', '--name-only', base, 'HEAD'], cwd);
  // Fail CLOSED on git errors: gitCapture returns null when the diff
  // command itself fails (e.g. an unresolvable base SHA). Treating that
  // like an empty diff would make the gate pass vacuously — the exact
  // fail-open a coverage gate must never have. An empty string, by
  // contrast, is a genuinely empty diff.
  if (diffOutput === null) {
    throw new Error(
      `git diff against base "${base}" (${source}) failed — the base is ` +
        `unresolvable in this repo. Refusing to pass the gate on a broken diff.`,
    );
  }
  const changedPaths = diffOutput.split('\n').filter(Boolean);

  const sourceFiles = changedPaths.filter((relativePath) => {
    // Deleted/renamed-away files must not crash the gate: skip anything
    // that no longer exists on disk.
    if (!existsSync(path.join(cwd, relativePath))) {
      return false;
    }
    return isTrackedSourceFile(relativePath);
  });

  return { base, source, sourceFiles };
}

function readThreshold(cwd) {
  const packageJsonPath = path.join(cwd, 'package.json');
  const packageJson = JSON.parse(readFileSync(packageJsonPath, 'utf8'));
  const threshold = packageJson.deployShield?.changedFileCoverage;
  if (typeof threshold !== 'number') {
    throw new Error(
      `missing "deployShield.changedFileCoverage" in ${packageJsonPath} — add a number (e.g. 85) to set the changed-file coverage threshold.`,
    );
  }
  return threshold;
}

function readCoverageReport(cwd) {
  const coveragePath = path.join(cwd, 'coverage', 'coverage-final.json');
  if (!existsSync(coveragePath)) {
    throw new Error(
      `${coveragePath} not found — run \`pnpm vitest run --coverage\` first.`,
    );
  }
  return JSON.parse(readFileSync(coveragePath, 'utf8'));
}

/**
 * File-level statement coverage percentage. Files with zero instrumentable
 * statements (pure types) count as 100% / skip.
 */
function statementCoverage(fileEntry) {
  const statements = Object.values(fileEntry.s);
  if (statements.length === 0) {
    return 100;
  }
  const covered = statements.filter((hits) => hits > 0).length;
  return (covered / statements.length) * 100;
}

export async function main(options = {}) {
  const {
    cwd = process.cwd(),
    env = process.env,
    stdout = (message) => console.log(message),
    stderr = (message) => console.error(message),
  } = options;

  let sourceFiles;
  try {
    ({ sourceFiles } = listChangedSourceFiles({ cwd, env }));
  } catch (error) {
    stderr(`changed-coverage: ${error.message}`);
    return 1;
  }

  if (sourceFiles.length === 0) {
    stdout('changed-coverage: nothing to check (no changed source files)');
    return 0;
  }

  let threshold;
  let coverageReport;
  try {
    threshold = readThreshold(cwd);
    coverageReport = readCoverageReport(cwd);
  } catch (error) {
    stderr(`changed-coverage: ${error.message}`);
    return 1;
  }

  const failures = [];
  for (const relativePath of sourceFiles) {
    const absolutePath = path.resolve(cwd, relativePath);
    const fileEntry = coverageReport[absolutePath];
    // A changed source file absent from the coverage report counts as 0%
    // — this is load-bearing (see vitest.config.ts's coverage.include note).
    const percent = fileEntry ? statementCoverage(fileEntry) : 0;
    if (percent < threshold) {
      failures.push({ relativePath, percent });
    }
  }

  if (failures.length > 0) {
    stderr(
      `changed-coverage: ${failures.length} changed file(s) below the ${threshold}% threshold:`,
    );
    for (const { relativePath, percent } of failures) {
      stderr(
        `  - ${relativePath}: ${percent.toFixed(1)}% (threshold ${threshold}%)`,
      );
    }
    return 1;
  }

  stdout(
    `changed-coverage: all ${sourceFiles.length} changed file(s) meet the ${threshold}% threshold`,
  );
  return 0;
}

const isMain =
  process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href;
if (isMain) {
  // Set exitCode rather than calling process.exit() so buffered stdout/stderr
  // (async when piped to a non-TTY, e.g. in CI or hooks) flushes before exit.
  process.exitCode = await main();
}
