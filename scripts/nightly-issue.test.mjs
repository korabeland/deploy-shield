import { execFileSync } from 'node:child_process';
import {
  chmodSync,
  mkdtempSync,
  readFileSync,
  rmSync,
  writeFileSync,
} from 'node:fs';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { afterEach, describe, expect, it } from 'vitest';

const SCRIPT = path.join(
  path.dirname(fileURLToPath(import.meta.url)),
  'nightly-issue.sh',
);

const dirsToClean = [];

afterEach(() => {
  while (dirsToClean.length > 0) {
    rmSync(dirsToClean.pop(), { recursive: true, force: true });
  }
});

/**
 * Runs nightly-issue.sh with a stub `gh` earlier on PATH that logs every
 * invocation and answers `issue list` with a canned issue number.
 */
function runWithStub({ openIssueNumber = '', env = {} } = {}) {
  const dir = mkdtempSync(path.join(tmpdir(), 'nightly-issue-'));
  dirsToClean.push(dir);
  const callLog = path.join(dir, 'calls.log');
  const stub = path.join(dir, 'gh');
  writeFileSync(
    stub,
    `#!/usr/bin/env bash
echo "$*" >> "${callLog}"
if [ "$1" = "issue" ] && [ "$2" = "list" ]; then
  printf '%s' "${openIssueNumber}"
fi
exit 0
`,
  );
  chmodSync(stub, 0o755);

  let exitCode = 0;
  try {
    execFileSync('bash', [SCRIPT], {
      env: {
        ...process.env,
        PATH: `${dir}:${process.env.PATH}`,
        RUN_URL: 'https://example.com/runs/1',
        GATE_SUMMARY: 'semgrep: failure',
        ...env,
      },
      stdio: 'pipe',
    });
  } catch (error) {
    exitCode = error.status ?? 1;
  }

  let calls = [];
  try {
    calls = readFileSync(callLog, 'utf8').trim().split('\n');
  } catch {
    // no gh calls made
  }
  return { exitCode, calls };
}

describe('nightly-issue.sh', () => {
  it('creates a labeled issue when none is open', () => {
    const { exitCode, calls } = runWithStub();

    expect(exitCode).toBe(0);
    expect(calls.some((c) => c.startsWith('label create'))).toBe(true);
    expect(calls.some((c) => c.startsWith('issue create'))).toBe(true);
    expect(calls.some((c) => c.startsWith('issue comment'))).toBe(false);
  });

  it('comments on the open issue instead of creating a second one', () => {
    const { exitCode, calls } = runWithStub({ openIssueNumber: '42' });

    expect(exitCode).toBe(0);
    expect(calls.some((c) => c.startsWith('issue comment 42'))).toBe(true);
    expect(calls.some((c) => c.startsWith('issue create'))).toBe(false);
  });

  it('fails fast with a clear error when RUN_URL is missing', () => {
    const { exitCode, calls } = runWithStub({ env: { RUN_URL: '' } });

    expect(exitCode).not.toBe(0);
    // Nothing should have been filed before the guard fired.
    expect(calls.some((c) => c.startsWith('issue'))).toBe(false);
  });
});
