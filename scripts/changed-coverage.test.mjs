import { execFileSync } from 'node:child_process';
import { mkdtempSync, mkdirSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { afterEach, describe, expect, it } from 'vitest';

import { main } from './changed-coverage.mjs';

/**
 * Environment for git subprocesses: the real environment with every GIT_*
 * variable stripped, so `cwd` alone decides which repo git acts on. Without
 * this, running the suite inside a git hook (which exports GIT_DIR /
 * GIT_WORK_TREE / GIT_INDEX_FILE) would redirect these throwaway-repo commits
 * at the real repository — silently committing fixtures onto the branch under
 * test. Mirrors the gate script's own GIT_ENV.
 */
const GIT_ENV = (() => {
  const env = { ...process.env };
  for (const key of Object.keys(env)) {
    if (key.startsWith('GIT_')) {
      delete env[key];
    }
  }
  return env;
})();

/**
 * Builds a real (but throwaway) git repo under a temp dir so the base
 * resolution + `git diff` logic is exercised end to end, not mocked.
 */
function createRepo() {
  const dir = mkdtempSync(path.join(tmpdir(), 'changed-coverage-'));
  git(dir, ['init', '-q', '-b', 'main']);
  git(dir, ['config', 'user.email', 'test@example.com']);
  git(dir, ['config', 'user.name', 'Test']);
  return dir;
}

function git(cwd, args) {
  execFileSync('git', args, { cwd, stdio: 'ignore', env: GIT_ENV });
}

function writeSourceFile(repoDir, relativePath, contents) {
  const fullPath = path.join(repoDir, relativePath);
  mkdirSync(path.dirname(fullPath), { recursive: true });
  writeFileSync(fullPath, contents);
}

function writePackageJson(repoDir, threshold = 85) {
  writeSourceFile(
    repoDir,
    'package.json',
    JSON.stringify({ deployShield: { changedFileCoverage: threshold } }),
  );
}

function commitAll(repoDir, message) {
  git(repoDir, ['add', '-A']);
  git(repoDir, ['commit', '-q', '-m', message]);
}

/** Minimal Istanbul coverage-final.json fixture for one file. */
function coverageEntry(absolutePath, totalStatements, coveredCount) {
  const s = {};
  for (let i = 0; i < totalStatements; i += 1) {
    s[String(i)] = i < coveredCount ? 1 : 0;
  }
  return {
    path: absolutePath,
    statementMap: {},
    fnMap: {},
    branchMap: {},
    s,
    f: {},
    b: {},
  };
}

function writeCoverageReport(repoDir, entries) {
  const report = {};
  for (const { relativePath, totalStatements, coveredCount } of entries) {
    const absolutePath = path.join(repoDir, relativePath);
    report[absolutePath] = coverageEntry(
      absolutePath,
      totalStatements,
      coveredCount,
    );
  }
  writeSourceFile(
    repoDir,
    'coverage/coverage-final.json',
    JSON.stringify(report),
  );
}

function collector() {
  const lines = [];
  return { lines, log: (message) => lines.push(message) };
}

/** Runs the gate against a repo, capturing exit code and joined output. */
async function runGate(repoDir, env = {}) {
  const stdout = collector();
  const stderr = collector();
  const code = await main({
    cwd: repoDir,
    env,
    stdout: stdout.log,
    stderr: stderr.log,
  });
  return {
    code,
    stdout: stdout.lines.join('\n'),
    stderr: stderr.lines.join('\n'),
  };
}

function writeSingleFileCoverage(
  repoDir,
  relativePath,
  totalStatements,
  coveredCount,
) {
  writeCoverageReport(repoDir, [
    { relativePath, totalStatements, coveredCount },
  ]);
}

const reposToClean = [];

afterEach(() => {
  while (reposToClean.length > 0) {
    const dir = reposToClean.pop();
    rmSync(dir, { recursive: true, force: true });
  }
});

function trackedRepo() {
  const dir = createRepo();
  reposToClean.push(dir);
  return dir;
}

describe('changed-coverage', () => {
  it('exits 0 when a changed file is at or above the threshold', async () => {
    const repoDir = trackedRepo();
    writePackageJson(repoDir);
    commitAll(repoDir, 'initial scaffold');

    writeSourceFile(
      repoDir,
      'packages/pkg/src/good.ts',
      'export const good = 1;\n',
    );
    commitAll(repoDir, 'add good.ts');

    writeSingleFileCoverage(repoDir, 'packages/pkg/src/good.ts', 10, 9);

    const result = await runGate(repoDir);

    expect(result.code).toBe(0);
    expect(result.stdout).toMatch(/meet the 85% threshold/);
  });

  it('exits 1 and lists a changed file below the threshold with its percentage', async () => {
    const repoDir = trackedRepo();
    writePackageJson(repoDir);
    commitAll(repoDir, 'initial scaffold');

    writeSourceFile(
      repoDir,
      'packages/pkg/src/bad.ts',
      'export const bad = 1;\n',
    );
    commitAll(repoDir, 'add bad.ts');

    writeSingleFileCoverage(repoDir, 'packages/pkg/src/bad.ts', 5, 3);

    const result = await runGate(repoDir);

    expect(result.code).toBe(1);
    expect(result.stderr).toContain('packages/pkg/src/bad.ts');
    expect(result.stderr).toContain('60.0%');
  });

  it('treats a changed file absent from the coverage report as 0% and exits 1', async () => {
    const repoDir = trackedRepo();
    writePackageJson(repoDir);
    commitAll(repoDir, 'initial scaffold');

    writeSourceFile(
      repoDir,
      'packages/pkg/src/missing.ts',
      'export const missing = 1;\n',
    );
    commitAll(repoDir, 'add missing.ts');

    // Coverage report exists but has no entry for missing.ts.
    writeCoverageReport(repoDir, []);

    const result = await runGate(repoDir);

    expect(result.code).toBe(1);
    expect(result.stderr).toContain('packages/pkg/src/missing.ts');
    expect(result.stderr).toContain('0.0%');
  });

  it('exits 0 with "nothing to check" for a docs-only diff', async () => {
    const repoDir = trackedRepo();
    writePackageJson(repoDir);
    commitAll(repoDir, 'initial scaffold');

    writeSourceFile(repoDir, 'docs/readme.md', '# hello\n');
    commitAll(repoDir, 'add docs');

    const result = await runGate(repoDir);

    expect(result.code).toBe(0);
    expect(result.stdout).toContain('nothing to check');
  });

  it('does not crash on a deleted file in the diff', async () => {
    const repoDir = trackedRepo();
    writePackageJson(repoDir);
    writeSourceFile(
      repoDir,
      'packages/pkg/src/deleted.ts',
      'export const deleted = 1;\n',
    );
    commitAll(repoDir, 'initial scaffold with deleted.ts');

    git(repoDir, ['rm', '-q', 'packages/pkg/src/deleted.ts']);
    commitAll(repoDir, 'remove deleted.ts');

    const result = await runGate(repoDir);

    expect(result.code).toBe(0);
    expect(result.stdout).toContain('nothing to check');
  });

  it('resolves the base via CHANGED_COVERAGE_BASE when set (tier 1)', async () => {
    const repoDir = trackedRepo();
    writePackageJson(repoDir);
    commitAll(repoDir, 'initial scaffold');
    const baseSha = execFileSync('git', ['rev-parse', 'HEAD'], {
      cwd: repoDir,
      encoding: 'utf8',
      env: GIT_ENV,
    }).trim();

    writeSourceFile(
      repoDir,
      'packages/pkg/src/good.ts',
      'export const good = 1;\n',
    );
    commitAll(repoDir, 'add good.ts');

    writeSingleFileCoverage(repoDir, 'packages/pkg/src/good.ts', 2, 2);

    const result = await runGate(repoDir, { CHANGED_COVERAGE_BASE: baseSha });

    expect(result.code).toBe(0);
    expect(result.stdout).toContain('meet the 85% threshold');
  });

  it('treats an all-zeros CHANGED_COVERAGE_BASE as unset and falls through', async () => {
    const repoDir = trackedRepo();
    writePackageJson(repoDir);
    commitAll(repoDir, 'initial scaffold');

    writeSourceFile(
      repoDir,
      'packages/pkg/src/good.ts',
      'export const good = 1;\n',
    );
    commitAll(repoDir, 'add good.ts');

    writeSingleFileCoverage(repoDir, 'packages/pkg/src/good.ts', 2, 2);

    // GitHub sets github.event.before to 40 zeros on branch creation /
    // force push — the script must fall through to HEAD~1, not crash.
    const result = await runGate(repoDir, {
      CHANGED_COVERAGE_BASE: '0'.repeat(40),
    });

    expect(result.code).toBe(0);
    expect(result.stdout).toContain('meet the 85% threshold');
  });

  it('fails closed when the base is unresolvable (bad CHANGED_COVERAGE_BASE)', async () => {
    const repoDir = trackedRepo();
    writePackageJson(repoDir);
    writeSourceFile(
      repoDir,
      'packages/pkg/src/good.ts',
      'export const good = 1;\n',
    );
    commitAll(repoDir, 'root commit');
    writeSingleFileCoverage(repoDir, 'packages/pkg/src/good.ts', 2, 2);

    // A garbage base must FAIL the gate, not pass it vacuously.
    const result = await runGate(repoDir, {
      CHANGED_COVERAGE_BASE: 'deadbeefdeadbeefdeadbeefdeadbeefdeadbeef',
    });

    expect(result.code).toBe(1);
    expect(result.stderr).toContain('unresolvable');
  });

  it('resolves the base via merge-base with origin default branch (tier 2)', async () => {
    // Simulate the normal local-developer path: a repo with an `origin`
    // remote whose default branch diverged from the feature branch.
    const originDir = trackedRepo();
    writePackageJson(originDir);
    writeSourceFile(
      originDir,
      'packages/pkg/src/base.ts',
      'export const base = 1;\n',
    );
    commitAll(originDir, 'base commit on main');

    const repoDir = mkdtempSync(path.join(tmpdir(), 'changed-coverage-clone-'));
    reposToClean.push(repoDir);
    execFileSync('git', ['clone', '-q', originDir, repoDir], {
      stdio: 'ignore',
      env: GIT_ENV,
    });
    git(repoDir, ['config', 'user.email', 'test@example.com']);
    git(repoDir, ['config', 'user.name', 'Test']);
    git(repoDir, ['checkout', '-q', '-b', 'feature']);
    writeSourceFile(
      repoDir,
      'packages/pkg/src/feature.ts',
      'export const feature = 1;\n',
    );
    commitAll(repoDir, 'feature work');
    writeSingleFileCoverage(repoDir, 'packages/pkg/src/feature.ts', 4, 4);

    // No CHANGED_COVERAGE_BASE: tier 2 must diff only the feature commit
    // (base.ts is on origin/main and must not be in the changed set —
    // its absence from the coverage report would otherwise fail the gate).
    const result = await runGate(repoDir);

    expect(result.code).toBe(0);
    expect(result.stdout).toContain('all 1 changed file(s)');
  });

  it('passes at exactly the threshold boundary (85%)', async () => {
    const repoDir = trackedRepo();
    writePackageJson(repoDir);
    commitAll(repoDir, 'initial scaffold');
    writeSourceFile(
      repoDir,
      'packages/pkg/src/edge.ts',
      'export const edge = 1;\n',
    );
    commitAll(repoDir, 'add edge.ts');
    // 17/20 = 85.0% — exactly at the threshold must PASS (< threshold fails).
    writeSingleFileCoverage(repoDir, 'packages/pkg/src/edge.ts', 20, 17);

    const result = await runGate(repoDir);

    expect(result.code).toBe(0);
  });

  it('errors clearly when deployShield config or coverage report is missing', async () => {
    const repoDir = trackedRepo();
    // package.json without the deployShield block:
    writeSourceFile(repoDir, 'package.json', '{}');
    writeSourceFile(repoDir, 'packages/pkg/src/x.ts', 'export const x = 1;\n');
    commitAll(repoDir, 'root');
    writeSingleFileCoverage(repoDir, 'packages/pkg/src/x.ts', 2, 2);

    const missingConfig = await runGate(repoDir);
    expect(missingConfig.code).toBe(1);
    expect(missingConfig.stderr).toContain('changedFileCoverage');

    // Restore config but remove the coverage report:
    writePackageJson(repoDir);
    rmSync(path.join(repoDir, 'coverage'), { recursive: true, force: true });
    const missingReport = await runGate(repoDir);
    expect(missingReport.code).toBe(1);
    expect(missingReport.stderr).toContain('pnpm vitest run --coverage');
  });

  it('falls back to the empty tree for a single-commit (root) repo', async () => {
    const repoDir = trackedRepo();
    writePackageJson(repoDir);
    writeSourceFile(
      repoDir,
      'packages/pkg/src/good.ts',
      'export const good = 1;\n',
    );
    commitAll(repoDir, 'root commit');

    writeSingleFileCoverage(repoDir, 'packages/pkg/src/good.ts', 2, 2);

    const result = await runGate(repoDir);

    expect(result.code).toBe(0);
    expect(result.stdout).toContain('meet the 85% threshold');
  });
});
