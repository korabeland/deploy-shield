#!/usr/bin/env bash
# Deploy Shield bootstrap script.
#
# GitHub's "Use this template" mechanism copies files but not repo settings —
# branch protection, secrets, and labels are manual per-repo work someone
# will otherwise skip. Run this once in a fresh clone to close that gap.
#
# Every step (except the preflight checks, which must run before any
# mutation) is idempotent: re-running this script is safe and detects
# already-applied state instead of erroring or duplicating it.

set -euo pipefail

RULESET_FILE=".github/rulesets/main.json"
# Vercel's Root Directory for the deployed service. The deploy workflow runs
# the Vercel CLI from the repo root so pnpm workspace symlinks resolve; this
# setting is what tells Vercel which subdirectory is the app.
DEFAULT_ROOT_DIR="services/example-service"
NIGHTLY_LABEL="nightly-failure"
NIGHTLY_LABEL_COLOR="B60205"
NIGHTLY_LABEL_DESC="Filed automatically by the nightly deep-scan workflow"

# Populated by install_toolchain, read by verify_shims.
MISE_OK=0

# One "name|status|note" entry per step, printed by print_summary.
STEP_STATUS=()

log() {
  printf '%s\n' "$*"
}

warn() {
  printf 'WARNING: %s\n' "$*" >&2
}

err() {
  printf 'ERROR: %s\n' "$*" >&2
}

record_status() {
  STEP_STATUS+=("$1|$2|$3")
}

# Step 1: preflight — must pass before anything mutates repo state.
preflight() {
  log "==> Preflight checks"

  if ! command -v gh >/dev/null 2>&1; then
    err "GitHub CLI ('gh') not found. Install it: https://cli.github.com/"
    exit 1
  fi

  if ! gh auth status >/dev/null 2>&1; then
    err "'gh' is not authenticated. Run 'gh auth login' and re-run this script."
    exit 1
  fi

  if ! gh repo view >/dev/null 2>&1; then
    err "Could not resolve a GitHub repository from the current directory (no remote, or 'gh' can't see it). Run this script from inside a git clone with a GitHub remote."
    exit 1
  fi

  log "gh installed, authenticated, and a GitHub remote resolved."
  record_status "preflight" "done" ""
}

# Step 2: import the branch-protection ruleset.
apply_ruleset() {
  log "==> Importing branch-protection ruleset"
  local step="ruleset"

  if [[ ! -f "$RULESET_FILE" ]]; then
    warn "Ruleset file '$RULESET_FILE' not found — skipping."
    record_status "$step" "skipped" "ruleset file missing"
    return
  fi

  local existing_id
  existing_id=$(gh api "repos/{owner}/{repo}/rulesets" --jq '.[] | select(.name=="main") | .id' 2>/dev/null) || existing_id=""

  if [[ -n "$existing_id" ]]; then
    log "Ruleset 'main' already exists (id=$existing_id) — skipping."
    record_status "$step" "skipped" "already exists"
    return
  fi

  local output
  if output=$(gh api "repos/{owner}/{repo}/rulesets" --method POST --input "$RULESET_FILE" 2>&1); then
    log "Ruleset 'main' imported."
    record_status "$step" "done" ""
  elif printf '%s' "$output" | grep -qE 'HTTP (403|422)'; then
    warn "GitHub rejected the ruleset import (403/422). Required-check rulesets — and classic branch protection, which has the same constraint — need a public repo, or a paid plan for a private one. There is no free fallback; skipping this step."
    record_status "$step" "skipped" "403/422 — plan or visibility restriction"
  else
    warn "Failed to import ruleset: $output"
    record_status "$step" "warned" "unexpected gh api error"
  fi
}

# Step 3: Vercel secrets/vars — each prompt independently skippable.
setup_vercel() {
  log "==> Vercel wiring"
  local step="vercel"

  if [[ ! -t 0 ]]; then
    log "Non-interactive shell — skipping Vercel prompts. To set them directly:"
    log "  printf '%s' \"\$VERCEL_TOKEN\" | gh secret set VERCEL_TOKEN"
    log "  gh variable set VERCEL_ORG_ID --body \"<org id>\""
    log "  gh variable set VERCEL_PROJECT_ID --body \"<project id>\""
    log "And set the project's Root Directory (no CLI flag exists for it):"
    log "  curl -X PATCH \"https://api.vercel.com/v9/projects/<project id>?teamId=<org id>\" \\"
    log "    -H \"Authorization: Bearer \$VERCEL_TOKEN\" -H 'Content-Type: application/json' \\"
    log "    -d '{\"rootDirectory\":\"$DEFAULT_ROOT_DIR\"}'"
    record_status "$step" "skipped" "non-interactive stdin (commands printed)"
    return
  fi

  log "These are only needed for the deploy workflow (.github/workflows/deploy.yml). Press Enter to skip any prompt."

  local token="" org_id="" project_id="" any_set=0

  # `|| var=""` on each read: Ctrl-D (EOF) at a prompt makes `read` return
  # nonzero, which under `set -e` would abort the whole script mid-run with
  # no summary. EOF means "skip this prompt", same as a blank Enter.
  read -r -s -p "VERCEL_TOKEN (leave blank to skip): " token || token=""
  echo
  if [[ -n "$token" ]]; then
    if printf '%s' "$token" | gh secret set VERCEL_TOKEN; then
      log "VERCEL_TOKEN secret set."
      any_set=1
    else
      warn "Failed to set VERCEL_TOKEN secret."
    fi
  fi

  read -r -p "VERCEL_ORG_ID (leave blank to skip): " org_id || org_id=""
  if [[ -n "$org_id" ]]; then
    if gh variable set VERCEL_ORG_ID --body "$org_id"; then
      log "VERCEL_ORG_ID variable set."
      any_set=1
    else
      warn "Failed to set VERCEL_ORG_ID variable."
    fi
  fi

  read -r -p "VERCEL_PROJECT_ID (leave blank to skip): " project_id || project_id=""
  if [[ -n "$project_id" ]]; then
    if gh variable set VERCEL_PROJECT_ID --body "$project_id"; then
      log "VERCEL_PROJECT_ID variable set."
      any_set=1
    else
      warn "Failed to set VERCEL_PROJECT_ID variable."
    fi
  fi

  # Root Directory has no CLI flag, so it goes through the REST API. Without
  # it the deploy workflow — which runs from the repo root on purpose — has
  # no idea which subdirectory holds the service.
  if [[ -n "$token" && -n "$project_id" ]]; then
    local root_dir=""
    read -r -p "Service root directory [$DEFAULT_ROOT_DIR]: " root_dir || root_dir=""
    root_dir="${root_dir:-$DEFAULT_ROOT_DIR}"

    local api="https://api.vercel.com/v9/projects/${project_id}"
    if [[ -n "$org_id" ]]; then
      api="${api}?teamId=${org_id}"
    fi

    if curl -fsS -X PATCH "$api" \
      -H "Authorization: Bearer ${token}" \
      -H "Content-Type: application/json" \
      -d "{\"rootDirectory\":\"${root_dir}\"}" >/dev/null; then
      log "Vercel Root Directory set to '${root_dir}'."
    else
      warn "Could not set the Vercel Root Directory. Set it under Project Settings → General → Root Directory, or deploys will fail to find the service."
    fi
  fi

  if [[ "$any_set" -eq 1 ]]; then
    record_status "$step" "done" ""
  else
    record_status "$step" "skipped" "all prompts left blank"
  fi
}

# Step 4: nightly-failure label.
create_label() {
  log "==> Nightly-failure label"
  local step="label"

  # Idempotent via check-then-create (same pattern as apply_ruleset), rather
  # than `label create --force`: this lets the summary distinguish "already
  # there" from "just created" instead of reporting "done" on every run.
  if gh label list --json name --jq '.[].name' 2>/dev/null | grep -qx "$NIGHTLY_LABEL"; then
    log "Label '$NIGHTLY_LABEL' already exists — skipping."
    record_status "$step" "skipped" "already exists"
    return
  fi

  if gh label create "$NIGHTLY_LABEL" --description "$NIGHTLY_LABEL_DESC" --color "$NIGHTLY_LABEL_COLOR" >/dev/null 2>&1; then
    log "Label '$NIGHTLY_LABEL' created."
    record_status "$step" "done" ""
  else
    warn "Failed to create the '$NIGHTLY_LABEL' label."
    record_status "$step" "warned" "gh label create failed"
  fi
}

# Step 5: local toolchain — mise, pnpm dependencies, lefthook hooks.
install_toolchain() {
  log "==> Local toolchain"
  local step="toolchain"
  local pnpm_ok=0

  if ! command -v mise >/dev/null 2>&1; then
    err "mise not found. install mise: https://mise.jdx.dev"
  elif ! mise install; then
    err "'mise install' failed."
  else
    log "mise-managed tools installed."
    MISE_OK=1
  fi

  if ! command -v pnpm >/dev/null 2>&1; then
    err "pnpm not found. Run 'corepack enable' to get pnpm, then re-run this script."
  elif ! pnpm install --frozen-lockfile; then
    err "'pnpm install --frozen-lockfile' failed."
  elif ! pnpm exec lefthook install; then
    err "'pnpm exec lefthook install' failed."
  else
    log "Dependencies installed and lefthook hooks wired."
    pnpm_ok=1
  fi

  if [[ "$MISE_OK" -eq 1 && "$pnpm_ok" -eq 1 ]]; then
    record_status "$step" "done" ""
  elif [[ "$MISE_OK" -eq 1 || "$pnpm_ok" -eq 1 ]]; then
    record_status "$step" "warned" "partial success — see errors above"
  else
    record_status "$step" "warned" "mise and pnpm both failed"
  fi
}

# Step 6: post-check — mise shims must actually resolve on PATH.
verify_shims() {
  log "==> Post-check: mise shim resolution"
  local step="shim-check"

  if [[ "$MISE_OK" -ne 1 ]]; then
    log "Skipping shim check — mise install did not complete."
    record_status "$step" "skipped" "mise install did not complete"
    return
  fi

  if command -v gitleaks >/dev/null 2>&1; then
    log "mise shims resolve on PATH (gitleaks found)."
    record_status "$step" "done" ""
  else
    warn "mise-installed tools aren't resolving on PATH yet. Run: eval \"\$(mise activate zsh)\" — add that line to your shell rc file so the git hooks can find gitleaks, shellcheck, and friends."
    record_status "$step" "warned" "shims not resolving — PATH activation needed"
  fi
}

# Step 7: final summary.
print_summary() {
  log ""
  log "==> Setup summary"

  local entry name rest status note
  for entry in "${STEP_STATUS[@]}"; do
    name="${entry%%|*}"
    rest="${entry#*|}"
    status="${rest%%|*}"
    note="${rest#*|}"
    if [[ -n "$note" ]]; then
      printf '  [%s] %s — %s\n' "$status" "$name" "$note"
    else
      printf '  [%s] %s\n' "$status" "$name"
    fi
  done
}

main() {
  preflight
  apply_ruleset
  setup_vercel
  create_label
  install_toolchain
  verify_shims
  print_summary
}

main "$@"
