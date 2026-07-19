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
# Scenario f — pure type error rejected at pre-push (tsc), and by CI directly
# ---------------------------------------------------------------------------

scenario_f_typecheck() {
  section "Scenario f: type error rejected at pre-push (tsc)"

  # Single quotes + trailing semicolon so this is prettier-clean, and no
  # unused/undeclared identifiers so it's eslint-clean too — the only thing
  # wrong with this file is the type mismatch, so tsc is the sole rejector.
  cat >"$REPO/packages/contracts/src/gate-verify-bad-type.ts" <<'EOF'
export const gateVerifyBadType: number = 'not a number';
EOF

  (cd "$REPO" && git add packages/contracts/src/gate-verify-bad-type.ts)
  capture git commit -q -m "chore: add type error"
  if [ "$LAST_STATUS" -ne 0 ]; then
    record_fail "f-type-error-rejected-at-pre-push" \
      "setup for this scenario failed: the commit itself was rejected at pre-commit (it should be lint- and format-clean — eslint does not duplicate tsc's diagnostics):
$LAST_OUTPUT"
    reset_repo
    return
  fi

  # On main, not a branch: changed-coverage resolves vacuously here (see
  # scenario d), so running on main keeps this leg's failure attributable to
  # typecheck alone.
  capture pnpm exec lefthook run pre-push
  if [ "$LAST_STATUS" -eq 0 ]; then
    record_fail "f-type-error-rejected-at-pre-push" "lefthook run pre-push unexpectedly SUCCEEDED"
  elif grep -qi "mise install" <<<"$LAST_OUTPUT"; then
    record_fail "f-type-error-rejected-at-pre-push" \
      "pre-push failed, but for the wrong reason:
$LAST_OUTPUT"
  elif grep -q "error TS" <<<"$LAST_OUTPUT"; then
    record_pass "f-type-error-rejected-at-pre-push"
  else
    record_fail "f-type-error-rejected-at-pre-push" \
      "pre-push failed, but output did not look like a tsc diagnostic:
$LAST_OUTPUT"
  fi

  # CI-parity leg: the typecheck job's exact command, run directly against
  # the same bad file.
  capture pnpm exec tsc --noEmit -p tsconfig.base.json
  if [ "$LAST_STATUS" -eq 0 ]; then
    record_fail "f-type-error-rejected-in-ci" "CI's tsc command unexpectedly SUCCEEDED"
  elif grep -q "error TS" <<<"$LAST_OUTPUT"; then
    record_pass "f-type-error-rejected-in-ci"
  else
    record_fail "f-type-error-rejected-in-ci" \
      "CI's tsc command failed, but output did not look like a tsc diagnostic:
$LAST_OUTPUT"
  fi

  reset_repo
}

# ---------------------------------------------------------------------------
# Scenario g — misformatted JSON rejected at pre-commit (prettier), and by
# CI's whole-tree run directly
# ---------------------------------------------------------------------------

scenario_g_prettier() {
  section "Scenario g: misformatted JSON rejected at pre-commit (prettier)"

  # JSON isn't touched by eslint, depcruise, or yamllint's globs — prettier
  # is the only hook left that can reject this file.
  printf '{"gateVerify":1,"badlyFormatted":true}\n' >"$REPO/gate-verify-bad-format.json"

  (cd "$REPO" && git add gate-verify-bad-format.json)
  capture git commit -q -m "chore: add misformatted json"

  if [ "$LAST_STATUS" -eq 0 ]; then
    record_fail "g-prettier-rejected-at-pre-commit" "git commit unexpectedly SUCCEEDED"
  elif grep -qi "mise install" <<<"$LAST_OUTPUT"; then
    record_fail "g-prettier-rejected-at-pre-commit" \
      "commit was rejected, but for the wrong reason:
$LAST_OUTPUT"
  elif grep -q "gate-verify-bad-format.json" <<<"$LAST_OUTPUT" || grep -qi "code style issues" <<<"$LAST_OUTPUT"; then
    record_pass "g-prettier-rejected-at-pre-commit"
  else
    record_fail "g-prettier-rejected-at-pre-commit" \
      "commit was rejected, but output did not look like a prettier detection:
$LAST_OUTPUT"
  fi

  # CI-parity leg: the lint job's exact command, run directly against the
  # whole tree with the same bad file present.
  capture pnpm exec prettier --check .
  if [ "$LAST_STATUS" -eq 0 ]; then
    record_fail "g-prettier-rejected-in-ci" "CI's prettier command unexpectedly SUCCEEDED"
  elif grep -q "gate-verify-bad-format.json" <<<"$LAST_OUTPUT"; then
    record_pass "g-prettier-rejected-in-ci"
  else
    record_fail "g-prettier-rejected-in-ci" \
      "CI's prettier command failed, but did not name the bad file:
$LAST_OUTPUT"
  fi

  reset_repo
}

# ---------------------------------------------------------------------------
# Scenario h — ShellCheck violation rejected at pre-commit, and by CI's
# workflow-lint job directly
# ---------------------------------------------------------------------------

scenario_h_shellcheck() {
  section "Scenario h: ShellCheck violation rejected at pre-commit (shellcheck)"

  mkdir -p "$REPO/scripts"

  # SC2086 (unquoted variable) is info-level and doesn't fail a bare
  # `shellcheck` invocation. An unassigned-variable reference (SC2154) is a
  # warning-level finding that does — verified empirically against the
  # hook's exact invocation before writing this fixture.
  cat >"$REPO/scripts/gate-verify-bad.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
rm -rf "$undefined_var/cache"
EOF

  (cd "$REPO" && git add scripts/gate-verify-bad.sh)
  capture git commit -q -m "chore: add shellcheck violation"

  if [ "$LAST_STATUS" -eq 0 ]; then
    record_fail "h-shellcheck-rejected-at-pre-commit" "git commit unexpectedly SUCCEEDED"
  elif grep -qi "mise install" <<<"$LAST_OUTPUT"; then
    record_fail "h-shellcheck-rejected-at-pre-commit" \
      "commit was rejected, but for the wrong reason:
$LAST_OUTPUT"
  elif grep -q "SC[0-9]\{4\}" <<<"$LAST_OUTPUT"; then
    record_pass "h-shellcheck-rejected-at-pre-commit"
  else
    record_fail "h-shellcheck-rejected-at-pre-commit" \
      "commit was rejected, but output did not look like a shellcheck detection:
$LAST_OUTPUT"
  fi

  # CI-parity leg: the workflow-lint job's exact shellcheck invocation,
  # covering both globs it scans (this fixture's path matters — it must
  # land under scripts/, one of the two globs CI actually shellchecks).
  # Globs are quoted and left to `sh -c` to expand: capture() cd's into
  # $REPO first, but unquoted globs here would expand against THIS script's
  # cwd (the real repo) before capture ever runs, silently shellchecking
  # the wrong tree.
  capture sh -c 'shellcheck scripts/*.sh tests/gates/*.sh'
  if [ "$LAST_STATUS" -eq 0 ]; then
    record_fail "h-shellcheck-rejected-in-ci" "CI's shellcheck command unexpectedly SUCCEEDED"
  elif grep -q "SC[0-9]\{4\}" <<<"$LAST_OUTPUT"; then
    record_pass "h-shellcheck-rejected-in-ci"
  else
    record_fail "h-shellcheck-rejected-in-ci" \
      "CI's shellcheck command failed, but output did not look like a shellcheck detection:
$LAST_OUTPUT"
  fi

  reset_repo
}

# ---------------------------------------------------------------------------
# Scenario i — over-length comment rejected at pre-commit (yamllint), and by
# CI's whole-tree run directly
# ---------------------------------------------------------------------------

scenario_i_yamllint() {
  section "Scenario i: over-length comment rejected at pre-commit (yamllint)"

  # A properly formatted mapping, so prettier leaves this file alone — the
  # violation lives only in a >120-char comment, which prettier does not
  # rewrap. The comment must be multiple words: yamllint's
  # allow-non-breakable-words lets a single unbreakable "word" run past the
  # limit, which would silently defeat this fixture.
  cat >"$REPO/gate-verify-bad.yml" <<'EOF'
# this is a deliberately long comment line used only to trip the yamllint line length rule without tripping prettier formatting checks
gateVerify: true
EOF

  (cd "$REPO" && git add gate-verify-bad.yml)
  capture git commit -q -m "chore: add yamllint violation"

  if [ "$LAST_STATUS" -eq 0 ]; then
    record_fail "i-yamllint-rejected-at-pre-commit" "git commit unexpectedly SUCCEEDED"
  elif grep -qi "mise install" <<<"$LAST_OUTPUT"; then
    record_fail "i-yamllint-rejected-at-pre-commit" \
      "commit was rejected, but for the wrong reason:
$LAST_OUTPUT"
  elif grep -qi "line too long" <<<"$LAST_OUTPUT"; then
    record_pass "i-yamllint-rejected-at-pre-commit"
  else
    record_fail "i-yamllint-rejected-at-pre-commit" \
      "commit was rejected, but output did not look like a yamllint detection:
$LAST_OUTPUT"
  fi

  # CI-parity leg: the workflow-lint job's exact yamllint invocation, run
  # directly against the whole tree with the same bad file present.
  capture yamllint -c .yamllint.yml .
  if [ "$LAST_STATUS" -eq 0 ]; then
    record_fail "i-yamllint-rejected-in-ci" "CI's yamllint command unexpectedly SUCCEEDED"
  elif grep -qi "line too long" <<<"$LAST_OUTPUT"; then
    record_pass "i-yamllint-rejected-in-ci"
  else
    record_fail "i-yamllint-rejected-in-ci" \
      "CI's yamllint command failed, but output did not look like a yamllint detection:
$LAST_OUTPUT"
  fi

  reset_repo
}

# ---------------------------------------------------------------------------
# Scenario j — undefined workflow context property rejected at pre-commit
# (actionlint), and by CI's workflow-lint job directly
# ---------------------------------------------------------------------------

scenario_j_actionlint() {
  section "Scenario j: undefined context property rejected at pre-commit (actionlint)"

  mkdir -p "$REPO/.github/workflows"

  # Properly formatted (prettier-clean) and under the line-length limit
  # (yamllint-clean) — the only defect is the undefined ${{ github.* }}
  # property, which only actionlint understands.
  cat >"$REPO/.github/workflows/gate-verify-bad.yml" <<'EOF'
name: gate-verify-bad

on:
  workflow_dispatch:

jobs:
  bad-job:
    runs-on: ubuntu-latest
    steps:
      - run: echo "${{ github.nonexistent_property }}"
EOF

  (cd "$REPO" && git add .github/workflows/gate-verify-bad.yml)
  capture git commit -q -m "chore: add actionlint violation"

  if [ "$LAST_STATUS" -eq 0 ]; then
    record_fail "j-actionlint-rejected-at-pre-commit" "git commit unexpectedly SUCCEEDED"
  elif grep -qi "mise install" <<<"$LAST_OUTPUT"; then
    record_fail "j-actionlint-rejected-at-pre-commit" \
      "commit was rejected, but for the wrong reason:
$LAST_OUTPUT"
  elif grep -qi "not defined" <<<"$LAST_OUTPUT" || grep -qi "actionlint" <<<"$LAST_OUTPUT"; then
    record_pass "j-actionlint-rejected-at-pre-commit"
  else
    record_fail "j-actionlint-rejected-at-pre-commit" \
      "commit was rejected, but output did not look like an actionlint detection:
$LAST_OUTPUT"
  fi

  # CI-parity leg: the workflow-lint job's exact command — actionlint
  # auto-discovers everything under .github/workflows/, no path argument.
  capture actionlint
  if [ "$LAST_STATUS" -eq 0 ]; then
    record_fail "j-actionlint-rejected-in-ci" "CI's actionlint command unexpectedly SUCCEEDED"
  elif grep -qi "not defined" <<<"$LAST_OUTPUT" || grep -qi "actionlint" <<<"$LAST_OUTPUT"; then
    record_pass "j-actionlint-rejected-in-ci"
  else
    record_fail "j-actionlint-rejected-in-ci" \
      "CI's actionlint command failed, but output did not look like an actionlint detection:
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
scenario_f_typecheck
scenario_g_prettier
scenario_h_shellcheck
scenario_i_yamllint
scenario_j_actionlint
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
