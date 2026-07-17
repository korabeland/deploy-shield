#!/usr/bin/env bash
#
# Files (or updates, label-deduplicated) a GitHub issue when the nightly
# workflow goes red — see SPEC.md's "Nightly failure" locked decision and
# the `report-failure` job in .github/workflows/nightly.yml, which is the
# only caller.
#
# Required environment:
#   GH_TOKEN     - token `gh` authenticates with (the workflow passes
#                  `github.token`)
#   RUN_URL      - URL of the nightly run that failed
#   GATE_SUMMARY - per-gate pass/fail summary to include in the issue body
#
# `gh issue list ... --json ... --jq ...` is used instead of a pipeline
# into grep/head so that "no open issues" is a normal empty-string result,
# not a non-zero exit from a piped command — the case `set -euo pipefail`
# would otherwise need special-casing for.

set -euo pipefail

LABEL="nightly-failure"
TITLE="Nightly gates failed"

: "${RUN_URL:?RUN_URL must be set}"
: "${GATE_SUMMARY:?GATE_SUMMARY must be set}"

body="Nightly gates failed.

Run: ${RUN_URL}

${GATE_SUMMARY}

To pull the failing step's specifics: \`gh run view <run-id> --log-failed\`
(the run id is the last path segment of the run URL above). Per-gate
diagnosis and sanctioned fixes: docs/gate-failures.md."

# The label normally exists (scripts/setup.sh creates it), but alerting
# must not hard-depend on the bootstrap having run — create it defensively.
# `--force` makes this idempotent: it updates the label if present rather
# than erroring.
gh label create "$LABEL" --force \
  --description "Filed automatically by the nightly deep-scan workflow" \
  --color B60205

open_issue_number=$(gh issue list --label "$LABEL" --state open --limit 1 --json number --jq '.[0].number // empty')

if [ -n "$open_issue_number" ]; then
  gh issue comment "$open_issue_number" --body "$body"
else
  gh issue create --label "$LABEL" --title "$TITLE" --body "$body"
fi
