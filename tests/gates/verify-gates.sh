#!/usr/bin/env bash
# Gate self-verification suite (SPEC.md "Gate self-verification", R2).
#
# Executable proof that the template's quality gates actually reject bad
# input, rather than trusting that they do. Builds ONE throwaway git repo in
# a temp dir from this repo's HEAD, installs the real lefthook hooks into
# it, and drives every scenario through a REAL `git commit` (or a real
# `lefthook run`) — this exercises install/PATH/config wiring, not just bare
# tool invocations. Runs locally (after `mise install && pnpm install`) and
# as CI's `self-verify` job.
#
# Bash 3.2 compatible on purpose: macOS ships bash 3.2 with no `local -n`
# namerefs, no associative arrays. Avoid both throughout.

set -euo pipefail

# ---------------------------------------------------------------------------
# Setup
# ---------------------------------------------------------------------------

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

WORKDIR="$(mktemp -d "${TMPDIR:-/tmp}/deploy-shield-gates.XXXXXX")"
REPO="$WORKDIR/repo"
BASE_COMMIT=""

PASS_COUNT=0
FAIL_COUNT=0
FAILED_SCENARIOS=()

cleanup() {
  rm -rf "$WORKDIR"
}
trap cleanup EXIT

section() {
  printf '\n=== %s ===\n' "$1"
}

record_pass() {
  PASS_COUNT=$((PASS_COUNT + 1))
  printf 'PASS: %s\n' "$1"
}

record_fail() {
  FAIL_COUNT=$((FAIL_COUNT + 1))
  FAILED_SCENARIOS+=("$1")
  printf 'FAIL: %s\n' "$1"
  if [ -n "${2:-}" ]; then
    printf -- '--- output ---\n%s\n--------------\n' "$2"
  fi
}

# Aborts the whole suite immediately — used only for setup preconditions
# that make every later scenario meaningless if false (e.g. the pre-commit
# hook never got installed).
die() {
  printf 'FATAL: %s\n' "$1" >&2
  exit 1
}

# Runs "$@" with $REPO as the working directory, capturing combined
# stdout+stderr into LAST_OUTPUT and the exit status into LAST_STATUS.
# Deliberately globals rather than `local -n` namerefs: macOS's bundled
# bash 3.2 doesn't support namerefs.
LAST_OUTPUT=""
LAST_STATUS=0
capture() {
  LAST_STATUS=0
  LAST_OUTPUT=$(cd "$REPO" && "$@" 2>&1) || LAST_STATUS=$?
}

# Runs "$@" with $REPO_ROOT (the real template tree) as the working
# directory — used for the CI-parity legs, which invoke the exact commands
# ci.yml runs against the real repo's actual devDependencies/config, just
# with a bad file staged in the temp repo copy. We still run these commands
# against $REPO (the temp copy holding the bad file), not $REPO_ROOT; see
# each scenario for the working directory it actually uses.

reset_repo() {
  git -C "$REPO" checkout -q main
  if git -C "$REPO" show-ref --verify --quiet refs/heads/scenario-uncovered; then
    git -C "$REPO" branch -D scenario-uncovered >/dev/null
  fi
  git -C "$REPO" reset --hard -q "$BASE_COMMIT"
  git -C "$REPO" clean -fdq
}

setup_start=$(date +%s)
section "Setup: building throwaway repo at $REPO"

mkdir -p "$REPO"
git init -q -b main "$REPO"
git -C "$REPO" config user.email "gate-verify@example.com"
git -C "$REPO" config user.name "Gate Verify"

# Copy the template tree in from the real repo's HEAD (git archive naturally
# excludes .git and anything not tracked — node_modules/coverage/etc. are
# gitignored, so they're never in HEAD to begin with).
git -C "$REPO_ROOT" archive --format=tar HEAD | tar -x -C "$REPO"

echo "Installing dependencies (pnpm install --frozen-lockfile)..."
install_start=$(date +%s)
(cd "$REPO" && pnpm install --frozen-lockfile)
install_end=$(date +%s)
echo "pnpm install: $((install_end - install_start))s"

(cd "$REPO" && pnpm exec lefthook install)

[ -f "$REPO/.git/hooks/pre-commit" ] ||
  die "lefthook install did not create .git/hooks/pre-commit — hook wiring is broken"

(cd "$REPO" && git add -A && git commit -q -m "chore: base commit for gate verification")
BASE_COMMIT="$(git -C "$REPO" rev-parse HEAD)"

setup_end=$(date +%s)
echo "Setup complete. Base commit: $BASE_COMMIT ($((setup_end - setup_start))s)"

# ---------------------------------------------------------------------------
# Scenario a — runtime-generated fake AWS key rejected at pre-commit
# ---------------------------------------------------------------------------

scenario_a_secret() {
  section "Scenario a: fake secret rejected at pre-commit (gitleaks)"

  # Built from concatenated parts at runtime — never a secret-shaped literal
  # in this script's own source, or gitleaks would flag the script itself
  # (this file is committed to the template it tests). Charset is base32
  # (A-Z, 2-7): gitleaks's aws-access-token rule matches
  # `(?:AKIA|ASIA|...)[A-Z2-7]{16}` specifically — 0/1/8/9 don't match, so a
  # naive A-Z0-9 charset silently produces a fixture gitleaks never flags.
  local prefix chars body i idx key
  prefix="AKIA"
  chars="ABCDEFGHIJKLMNOPQRSTUVWXYZ234567"
  body=""
  i=0
  while [ "$i" -lt 16 ]; do
    idx=$((RANDOM % ${#chars}))
    body="${body}${chars:$idx:1}"
    i=$((i + 1))
  done
  key="${prefix}${body}"

  {
    echo "# Runtime-generated fixture — never a real credential."
    echo "AWS_ACCESS_KEY_ID=${key}"
  } >"$REPO/leaked-secret.txt"

  (cd "$REPO" && git add leaked-secret.txt)
  capture git commit -q -m "chore: add fake secret"

  if [ "$LAST_STATUS" -eq 0 ]; then
    record_fail "a-secret-rejected-at-pre-commit" "git commit unexpectedly SUCCEEDED"
  elif grep -qi "mise install" <<<"$LAST_OUTPUT"; then
    record_fail "a-secret-rejected-at-pre-commit" \
      "commit was rejected, but because gitleaks is MISSING, not because it detected the secret:
$LAST_OUTPUT"
  elif grep -qi "leak" <<<"$LAST_OUTPUT"; then
    record_pass "a-secret-rejected-at-pre-commit"
  else
    record_fail "a-secret-rejected-at-pre-commit" \
      "commit was rejected, but output did not look like a gitleaks detection:
$LAST_OUTPUT"
  fi

  reset_repo
}

# ---------------------------------------------------------------------------
# Scenario b — ESLint violation rejected at pre-commit, and by CI directly
# ---------------------------------------------------------------------------

scenario_b_eslint() {
  section "Scenario b: ESLint violation rejected at pre-commit (eslint --max-warnings 0)"

  cat >"$REPO/packages/contracts/src/gate-verify-bad-lint.ts" <<'EOF'
export function badLint(): number {
  const unusedVariable = 42;
  return 1;
}
EOF

  (cd "$REPO" && git add packages/contracts/src/gate-verify-bad-lint.ts)
  capture git commit -q -m "chore: add eslint violation"

  if [ "$LAST_STATUS" -eq 0 ]; then
    record_fail "b-eslint-rejected-at-pre-commit" "git commit unexpectedly SUCCEEDED"
  elif grep -qi "mise install" <<<"$LAST_OUTPUT"; then
    record_fail "b-eslint-rejected-at-pre-commit" \
      "commit was rejected, but for the wrong reason:
$LAST_OUTPUT"
  elif grep -qi "no-unused-vars" <<<"$LAST_OUTPUT"; then
    record_pass "b-eslint-rejected-at-pre-commit"
  else
    record_fail "b-eslint-rejected-at-pre-commit" \
      "commit was rejected, but output did not name the expected eslint rule:
$LAST_OUTPUT"
  fi

  # CI-parity leg: the lint job's exact command, run directly (not via the
  # hook) against the same bad file — proves CI's own duplicate check
  # rejects it identically, since hooks are always --no-verify-bypassable.
  capture pnpm exec eslint . --max-warnings 0
  if [ "$LAST_STATUS" -eq 0 ]; then
    record_fail "b-eslint-rejected-in-ci" "CI's eslint command unexpectedly SUCCEEDED"
  elif grep -qi "no-unused-vars" <<<"$LAST_OUTPUT"; then
    record_pass "b-eslint-rejected-in-ci"
  else
    record_fail "b-eslint-rejected-in-ci" \
      "CI's eslint command failed, but output did not name the expected rule:
$LAST_OUTPUT"
  fi

  reset_repo
}

# ---------------------------------------------------------------------------
# Scenario c — cross-service import rejected at pre-commit (staged-file-
# scoped dependency-cruiser), and by CI's whole-tree run directly
# ---------------------------------------------------------------------------

scenario_c_cross_service() {
  section "Scenario c: cross-service import rejected at pre-commit (dependency-cruiser)"

  mkdir -p "$REPO/services/gate-verify-second-service/src"

  cat >"$REPO/services/gate-verify-second-service/package.json" <<'EOF'
{
  "name": "@deploy-shield/gate-verify-second-service",
  "version": "0.1.0",
  "private": true,
  "type": "module"
}
EOF

  # A tsconfig of its own is load-bearing here, not decorative: without one,
  # ESLint's typed-linting `projectService` bails with a parsing error for
  # this file (not in any tsconfig's `include`), which would ALSO fail the
  # commit — muddying whether dependency-cruiser specifically caught the
  # cross-service import. With a tsconfig, ESLint passes cleanly and only
  # dependency-cruiser is left to catch it.
  cat >"$REPO/services/gate-verify-second-service/tsconfig.json" <<'EOF'
{
  "extends": "../../tsconfig.base.json",
  "include": ["src"]
}
EOF

  cat >"$REPO/services/gate-verify-second-service/src/index.ts" <<'EOF'
import { handleHealth } from '../../example-service/src/health.js';

export function callHealth(): Response {
  return handleHealth(new Request('http://localhost/health'));
}
EOF

  (cd "$REPO" && git add services/gate-verify-second-service)
  capture git commit -q -m "chore: add cross-service import"

  if [ "$LAST_STATUS" -eq 0 ]; then
    record_fail "c-cross-service-import-rejected-at-pre-commit" \
      "git commit unexpectedly SUCCEEDED — staged-file-scoped dependency-cruiser did NOT catch a cross-service import. This is a REAL GATE BUG, not a test artifact."
  elif grep -qi "mise install" <<<"$LAST_OUTPUT"; then
    record_fail "c-cross-service-import-rejected-at-pre-commit" \
      "commit was rejected, but for the wrong reason:
$LAST_OUTPUT"
  elif grep -qi "services-no-cross-imports" <<<"$LAST_OUTPUT"; then
    record_pass "c-cross-service-import-rejected-at-pre-commit"
  else
    record_fail "c-cross-service-import-rejected-at-pre-commit" \
      "commit was rejected, but not by the services-no-cross-imports rule:
$LAST_OUTPUT"
  fi

  # CI-parity leg: the architecture job's exact command (whole-tree, not
  # staged-file-scoped) against the same bad tree.
  capture pnpm exec depcruise packages services
  if [ "$LAST_STATUS" -eq 0 ]; then
    record_fail "c-cross-service-import-rejected-in-ci" "CI's depcruise command unexpectedly SUCCEEDED"
  elif grep -qi "services-no-cross-imports" <<<"$LAST_OUTPUT"; then
    record_pass "c-cross-service-import-rejected-in-ci"
  else
    record_fail "c-cross-service-import-rejected-in-ci" \
      "CI's depcruise command failed, but not by the services-no-cross-imports rule:
$LAST_OUTPUT"
  fi

  reset_repo
}

# ---------------------------------------------------------------------------
# Scenario d — uncovered file rejected at pre-push (changed-coverage), on a
# feature branch (on main the coverage base resolves vacuously — see
# scripts/changed-coverage.mjs's base-resolution comment)
# ---------------------------------------------------------------------------

scenario_d_uncovered() {
  section "Scenario d: uncovered file rejected at pre-push (changed-coverage.mjs)"

  (cd "$REPO" && git checkout -q -b scenario-uncovered "$BASE_COMMIT")

  cat >"$REPO/services/example-service/src/gate-verify-uncovered.ts" <<'EOF'
export function double(value: number): number {
  return value * 2;
}
EOF

  (cd "$REPO" && git add services/example-service/src/gate-verify-uncovered.ts)
  capture git commit -q -m "feat: add uncovered function"
  if [ "$LAST_STATUS" -ne 0 ]; then
    record_fail "d-uncovered-file-rejected-at-pre-push" \
      "setup for this scenario failed: the commit itself was rejected at pre-commit (it should be lint-clean):
$LAST_OUTPUT"
    reset_repo
    return
  fi

  capture pnpm exec lefthook run pre-push
  if [ "$LAST_STATUS" -eq 0 ]; then
    record_fail "d-uncovered-file-rejected-at-pre-push" "lefthook run pre-push unexpectedly SUCCEEDED"
  elif grep -qi "mise install" <<<"$LAST_OUTPUT"; then
    record_fail "d-uncovered-file-rejected-at-pre-push" \
      "pre-push failed, but for the wrong reason:
$LAST_OUTPUT"
  elif grep -q "gate-verify-uncovered.ts" <<<"$LAST_OUTPUT"; then
    record_pass "d-uncovered-file-rejected-at-pre-push"
  else
    record_fail "d-uncovered-file-rejected-at-pre-push" \
      "pre-push failed, but did not name the uncovered file:
$LAST_OUTPUT"
  fi

  reset_repo
}

# ---------------------------------------------------------------------------
# Scenario e — positive control: a clean, well-formed, tested change commits
# and passes pre-push on main (catches gates so broken they reject
# everything)
# ---------------------------------------------------------------------------

scenario_e_positive_control() {
  section "Scenario e: positive control (clean change passes both tiers on main)"

  printf '\n// Gate self-verification positive control: comment-only change.\n' \
    >>"$REPO/services/example-service/src/health.ts"

  (cd "$REPO" && git add services/example-service/src/health.ts)
  capture git commit -q -m "chore: comment-only positive control"
  if [ "$LAST_STATUS" -ne 0 ]; then
    record_fail "e-positive-control-commit-succeeds" \
      "clean, well-formed change was unexpectedly REJECTED at pre-commit:
$LAST_OUTPUT"
    reset_repo
    return
  fi
  record_pass "e-positive-control-commit-succeeds"

  capture pnpm exec lefthook run pre-push
  if [ "$LAST_STATUS" -ne 0 ]; then
    record_fail "e-positive-control-pre-push-succeeds" \
      "clean, well-formed change was unexpectedly REJECTED at pre-push:
$LAST_OUTPUT"
  else
    record_pass "e-positive-control-pre-push-succeeds"
  fi

  reset_repo
}

# ---------------------------------------------------------------------------
# Scenario matrix
# ---------------------------------------------------------------------------

scenario_a_secret
scenario_b_eslint
scenario_c_cross_service
scenario_d_uncovered
scenario_e_positive_control

suite_end=$(date +%s)

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------

section "Summary"
echo "Passed: $PASS_COUNT"
echo "Failed: $FAIL_COUNT"
echo "Total wall clock: $((suite_end - setup_start))s"

if [ "$FAIL_COUNT" -ne 0 ]; then
  echo ""
  echo "Failed scenarios:"
  for scenario in "${FAILED_SCENARIOS[@]}"; do
    echo "  - $scenario"
  done
  exit 1
fi

echo ""
echo "All gate self-verification scenarios passed."
