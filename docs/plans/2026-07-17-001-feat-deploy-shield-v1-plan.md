---
title: "feat: Deploy Shield v1 — quality-gated pipeline template"
type: feat
status: active
date: 2026-07-17
deepened: 2026-07-17
origin: SPEC.md
---

# feat: Deploy Shield v1 — quality-gated pipeline template

## Summary

Build the Deploy Shield template repository end-to-end: a pnpm/TypeScript monorepo skeleton (contracts package + one deployable example service), four gate tiers (fast lefthook pre-commit, heavy pre-push, 7 CI checks + a `gate` aggregator, nightly deep scans that auto-file issues), a CI-only Vercel deploy path, a one-shot bootstrap script that applies branch-protection rulesets and secrets, and a self-verification suite proving the gates actually reject bad input.

---

## Problem Frame

AI-generated code ships fast but needs an enforced quality bar; the bar must be machinery, not discipline. SPEC.md (v1.1) locks all product decisions — this plan sequences the build. All tool versions and config surfaces below were verified against live registries on 2026-07-17 (see Sources); several differ materially from what a 2024-trained model would assume.

---

## Requirements

Traced to SPEC.md acceptance criteria:

- R1. `scripts/setup.sh` in a fresh clone yields working pre-commit and pre-push gates (mise install → pnpm install → lefthook install → ruleset + secrets).
- R2. Gate self-verification passes: fake secret, lint warning, cross-service import each rejected at pre-commit; untested change rejected at pre-push; clean commit succeeds. Runs in the template's own CI.
- R3. A PR shows the CI checks — the 7 quality checks plus the OSV scan and the `self-verify` job — aggregated by `gate`; the shipped ruleset requires only `gate`; setup.sh applies it.
- R4. Merge to `main` deploys to Vercel only when checks are green; the example service is minimally deployable end-to-end.
- R5. Nightly workflow runs Semgrep, per-package incremental Stryker, and a license allowlist audit; failure files/updates one label-deduplicated issue via `gh`.
- R6. All thresholds (coverage 85, duplication 3, mutation high 80 / break 70) live in visible, obvious config locations.
- R7. The repo is packageable as a public GitHub product: MIT LICENSE, downstream agent instructions shipped in every clone, gate-failure playbook, SECURITY.md, CHANGELOG with semver releases, and a documented repo-metadata checklist (template flag, topics, demo PR).

---

## Scope Boundaries

- No installable CLI, no Python track, no auth/feature-flag infrastructure, no enforced database-per-service (SPEC.md exclusions).
- No SonarCloud, CodeQL, or any paid/SaaS dependency; no third-party GitHub Actions for issue filing or Vercel deploys (plain `gh` / Vercel CLI).
- No update-propagation mechanism to downstream clones (documented limitation; v2 candidate).
- No Renovate/Dependabot config in v1.

### Deferred to Follow-Up Work

- Template-update propagation tooling: future iteration (essentially the rejected CLI).
- Dependabot/Renovate preset: trivial per-project addition, add on demand.

---

## Context & Research

### Relevant Code and Patterns

Greenfield — no existing code. SPEC.md and CLAUDE.md (both authored 2026-07-17) are the governing documents.

### External References (verified 2026-07-17, versions pinned)

- lefthook 2.1.10 — **v2 breaking changes**: `jobs` replaces `commands`, `skip_output` removed, glob-only excludes. pnpm 10 blocks postinstall: lefthook must be in `onlyBuiltDependencies`.
- gitleaks 8.30.1 — `protect`/`detect` deprecated; use `gitleaks git --pre-commit --redact --staged`. Action: `gitleaks/gitleaks-action@v3` (needs `GITLEAKS_LICENSE` for org-owned repos; personal accounts exempt).
- dependency-cruiser 18.1.0 — Node ≥22; `$1` back-reference idiom for "siblings forbidden" rules.
- jscpd 5.0.12 — gitignore-aware by default; `threshold: 3` exits non-zero when exceeded.
- Vitest 4.1.10 + @vitest/coverage-v8 (lockstep) — **`vitest.workspace.ts` is gone** (use `test.projects`); **`coverage.all` removed** (explicit `coverage.include` globs mandatory or untested files are invisible); `coverage-final.json` via `json` reporter still current.
- Stryker 9.6.1 (`@stryker-mutator/vitest-runner` official, version-locked) — no workspace orchestration: per-package configs; `incremental: true` with cached `reports/stryker-incremental.json`; `break` defaults to null.
- Semgrep 1.170.0 — run in `semgrep/semgrep` container; `semgrep scan --config p/... --error`; **npm `semgrep` package is a placeholder — never install**.
- OSV-Scanner 2.4.0 — consumed as reusable workflows (`google/osv-scanner-action/.github/workflows/osv-scanner-reusable*.yml@v2.3.8`); pnpm-lock.yaml natively supported; v2 CLI syntax differs from v1.
- actionlint 1.7.12 — no first-party action; download-script pattern in CI, mise locally. yamllint is Python-only: pip in CI, mise locally.
- license-checker-rseidelsohn 5.0.1 (published 2026-07-15) — `--onlyAllow "MIT;Apache-2.0;ISC;BSD-2-Clause;BSD-3-Clause" --excludePrivatePackages`. Original license-checker abandoned.
- Vercel CLI 56.x (pin as devDependency) — `vercel pull --yes --environment=… && vercel build && vercel deploy --prebuilt`; `"git": {"deploymentEnabled": false}` in vercel.json; bot doesn't comment on CLI deploys → post sticky PR comment manually.
- Rulesets over classic branch protection — exportable/importable JSON; `gh api repos/{o}/{r}/rulesets --method POST --input …`; `integration_id: 15368` (GitHub Actions) prevents check-name spoofing. **Caveat: rulesets on private repos require a paid plan — and classic branch protection has the same paid-only constraint on private repos, so there is no free fallback.** setup.sh detects the 403 and skips with a clear warning.
- mise — 2026 consensus for pinning non-npm binaries (gitleaks, semgrep via pipx backend, osv-scanner, shellcheck, actionlint, yamllint); `jdx/mise-action` gives identical versions in CI.
- Hook latency consensus: <10s hard ceiling, 3–5s target at pre-commit; heavy gates at pre-push; CI re-runs everything because `--no-verify` always exists.

---

## Key Technical Decisions

- **Pre-commit stays ~3–5s; typecheck, jscpd, changed-file coverage run at pre-push** — past ~10s, humans and agents reach for `--no-verify` (SPEC v1.1 revision, user-approved).
- **Changed-file coverage = file-level coverage of changed files** (parse `coverage-final.json`, intersect with `git diff --name-only <base>`, fail <85%) — simpler than changed-*lines* coverage; diff-cover/covguard noted in docs as upgrades if line-level is ever wanted.
- **Single `gate` aggregator is the only required check** — `needs:` all 7, `if: always()`, fails unless every result is success. One stable name in the ruleset; renames/additions never touch repo settings.
- **All 8 CI jobs in one always-running workflow, no `paths:` triggers** — a required check in a path-filtered workflow leaves non-matching PRs waiting forever; path-based skipping happens inside jobs.
- **Nightly-failure issues via hand-rolled `gh` steps, label-deduplicated** — zero third-party action supply-chain surface in a security-posture template; dedupe by label, not title.
- **Fake secrets for self-verification are generated at test runtime, never committed** — committed fixtures would trip GitHub push protection and gitleaks on the template itself.
- **Missing local binaries fail with "run `mise install`"** — never skip-if-missing; silently skipping a security gate is the anti-pattern.
- **Production deploys trigger on `workflow_run` (CI completed successfully on `main`), not on `push`** — this makes "no green, no deploy" structural even for ruleset-bypassing pushes (admins, `--bypass`), since the deploy job literally cannot start without a green CI run. Previews deploy directly on `pull_request` — they are inspection artifacts, intentionally not gated.
- **OSV-Scanner in CI runs as a reusable-workflow call (`uses:`) inside ci.yml, included in `gate`'s `needs`** — a job calling a reusable workflow is a legal `needs` dependency; if fork-PR permission constraints (`security-events: write`) surface in practice, the documented fallback is demoting it to advisory while the pre-push OSV scan stays blocking.
- **Example service is a minimal deployable HTTP endpoint** (Vercel Build Output–compatible) so the deploy job is real and testable, not dormant.

---

## Open Questions

### Resolved During Planning

- Hook latency vs. spec'd tier layout: resolved — heavy gates moved to pre-push (user-approved spec revision).
- Mutation threshold: resolved — `high: 80`, `break: 70`, documented ratchet.
- license-checker abandonment: resolved — license-checker-rseidelsohn (evergreen fork as fallback).
- Ruleset vs. classic protection: resolved — rulesets only; classic protection is equally paid-only on private repos, so setup.sh warns and skips there rather than shipping a dead fallback path.

### Deferred to Implementation

- Exact ESLint complexity rule set and limits: tune against the example service's real code, not in the abstract.
- Whether `vitest related {staged_files} --run` is fast enough to add as an optional pre-commit smoke: measure once the workspace exists.
- Stryker runtime on the example service: measure before deciding whether the nightly needs a per-package matrix or a single job.
- gitleaks-action's `GITLEAKS_LICENSE` handling: document the org-vs-personal split; verify behavior on first CI run.

---

## Output Structure

    deploy-shield/
    ├── SPEC.md / CLAUDE.md / README.md
    ├── AGENTS.md / LICENSE / SECURITY.md / CHANGELOG.md
    ├── docs/gate-failures.md / docs/maintaining.md
    ├── package.json / pnpm-workspace.yaml / pnpm-lock.yaml
    ├── tsconfig.base.json / vitest.config.ts
    ├── mise.toml                      # pinned non-npm binaries
    ├── lefthook.yml
    ├── eslint.config.mjs / .prettierrc.json
    ├── .dependency-cruiser.cjs / .jscpd.json / .yamllint.yml
    ├── .github/
    │   ├── workflows/ci.yml           # 7 checks + gate + self-verify
    │   ├── workflows/deploy.yml       # preview + production, Vercel CLI
    │   ├── workflows/nightly.yml      # semgrep, stryker, licenses → issue
    │   └── rulesets/main.json         # requires "gate"
    ├── packages/contracts/            # types, zod schemas, ports, seed data
    ├── services/example-service/      # deployable HTTP endpoint + vercel.json + stryker.config.json
    ├── scripts/
    │   ├── setup.sh                   # bootstrap: ruleset, secrets, label, installs
    │   ├── changed-coverage.mjs       # 85% gate on changed files
    │   └── nightly-issue.sh           # label-deduped gh issue file/update
    └── tests/gates/                   # self-verification meta-suite

---

## Implementation Units

### U1. Workspace scaffold and toolchain pinning

**Goal:** A bootable pnpm monorepo with every tool version pinned.

**Requirements:** R1

**Dependencies:** None

**Files:**
- Create: `package.json`, `pnpm-workspace.yaml`, `tsconfig.base.json`, `mise.toml`, `.gitignore`, `.editorconfig`

**Approach:**
- Node 22+ floor (dependency-cruiser 18 is the strictest). Root `package.json` holds devDependencies (exact-pinned) and the canonical scripts (`test`, `typecheck`, `lint`, `check`).
- `mise.toml` pins gitleaks 8.30.1, actionlint 1.7.12, shellcheck, osv-scanner 2.4.0, semgrep 1.170.0 (pipx backend), yamllint.
- pnpm 10 blocks postinstall scripts: add `lefthook` to `onlyBuiltDependencies` or hooks never install.

**Test scenarios:**
- Test expectation: none — pure scaffolding; exercised by every later unit and the U10 meta-suite.

**Verification:**
- Fresh clone: `mise install && pnpm install` completes; `pnpm -r exec node -e ""` sees all workspaces.

### U2. Contracts package and deployable example service

**Goal:** The multi-agent skeleton: shared contracts, one real service that Vercel can deploy, Vitest 4 wiring.

**Requirements:** R4, R6

**Dependencies:** U1

**Files:**
- Create: `packages/contracts/` (package.json, `src/` types + zod schemas + ports + seed data, tests)
- Create: `services/example-service/` (package.json, minimal HTTP endpoint in Vercel-deployable shape, `vercel.json` with `"git": {"deploymentEnabled": false}`, tests)
- Create: `vitest.config.ts` (root)
- Test: `packages/contracts/src/*.test.ts`, `services/example-service/src/*.test.ts`

**Approach:**
- Root Vitest config uses `test.projects: ["packages/*", "services/*"]` (Vitest 4 — the workspace file is gone).
- Coverage: `json` + `text` reporters; **explicit `coverage.include` globs** (`coverage.all` no longer exists — without include globs, untested files are invisible to the 85% gate).
- Example service: one contracts-typed HTTP endpoint (health/echo) — smallest thing that makes `vercel build` and the deploy job real.

**Test scenarios:**
- Happy path: zod schema in contracts accepts a valid payload and rejects a malformed one (field missing → parse error naming the field).
- Happy path: example-service endpoint returns a contracts-typed response for a valid request.
- Error path: endpoint returns a 4xx with a contracts-shaped error body for an invalid request.
- Integration: example-service imports types/schemas from `@deploy-shield/contracts` only (no relative cross-package path) — proves the workspace link the dep-cruiser rules assume.

**Verification:**
- `pnpm test` runs both projects; `pnpm vitest run --coverage` emits `coverage/coverage-final.json` including uncovered files.

### U3. Lint, format, and boundary configs

**Goal:** Every static gate has its config, with thresholds visible.

**Requirements:** R2, R6

**Dependencies:** U2 (rules need real code to validate against)

**Files:**
- Create: `eslint.config.mjs`, `.prettierrc.json`, `.dependency-cruiser.cjs`, `.jscpd.json`, `.yamllint.yml`

**Approach:**
- ESLint flat config: typescript-eslint strict + complexity rules (limits tuned against the example service — deferred detail).
- dependency-cruiser: the two SPEC rules using the `$1` back-reference idiom — `services/*` may not import other `services/*`; `services/*` may import only `packages/contracts` from `packages/*`. `doNotFollow: node_modules` so pnpm symlinks don't bypass path rules.
- `.jscpd.json`: `threshold: 3` (v5 is gitignore-aware by default — no manual excludes needed).

**Test scenarios:**
- Error path: a temporary file in service A importing from service B → `depcruise` exits non-zero naming the `services-no-cross-imports` rule. (Codified permanently in U10.)
- Happy path: current tree passes all four tools cleanly.

**Verification:**
- `pnpm lint`, `depcruise`, `jscpd .` all pass on the clean tree and the thresholds appear in their config files, not in scripts.

### U4. Changed-file coverage script

**Goal:** The one piece of custom glue: fail when any changed file is under 85% covered.

**Requirements:** R2, R6

**Dependencies:** U2

**Files:**
- Create: `scripts/changed-coverage.mjs`
- Test: `scripts/changed-coverage.test.mjs`

**Approach:**
- Run Vitest with coverage, parse `coverage-final.json` (Istanbul format), compute per-file statement coverage, intersect with `git diff --name-only <base>`, fail listing each file under 85%.
- Base-resolution chain (explicit, in this order): CI on a PR → the PR base SHA, with the base ref explicitly fetched in the `quality` job; CI on push → `github.event.before`; locally → merge-base with `origin/<default>` when a remote exists, else the previous commit, else the empty tree. Without this chain the gate passes vacuously in repos with no remote (merge-base with the local default branch is HEAD → empty diff).
- A changed source file **absent** from the coverage report counts as 0% (this is why `coverage.include` in U2 is load-bearing).
- Threshold read from one config location (root package.json `deployShield.changedFileCoverage` or equivalent) per R6.

**Execution note:** Test-first — the parsing/intersection logic is pure and this script is itself a gate; write the failing-file cases before the implementation.

**Test scenarios:**
- Happy path: changed file at 90% → exit 0.
- Error path: changed file at 60% → exit 1, file listed with its number.
- Edge case: changed file absent from the coverage report → treated as 0%, exit 1.
- Edge case: no changed TS files (docs-only diff) → exit 0 with "nothing to check".
- Edge case: deleted/renamed files in the diff don't crash the intersection.

**Verification:**
- Script test suite passes; running it on the clean tree with a synthetic diff behaves per the scenarios.

### U5. lefthook hooks — both local tiers

**Goal:** Tier 1 (~3–5s) and Tier 2 wired exactly as SPEC v1.1 splits them.

**Requirements:** R1, R2

**Dependencies:** U3, U4

**Files:**
- Create: `lefthook.yml`

**Approach:**
- lefthook 2.x `jobs` syntax (not `commands`), `parallel: true`.
- Pre-commit: gitleaks (`gitleaks git --pre-commit --redact --staged --verbose`), ESLint + Prettier on `{staged_files}`, dep-cruiser scoped to staged files, shellcheck/yamllint/actionlint gated by `glob:`.
- Pre-push: full tests, repo typecheck, jscpd, `changed-coverage.mjs`, `pnpm audit` + osv-scanner.
- Each non-npm binary wrapped: absent → fail with "run `mise install`" (never skip). Note the lefthook minimal-PATH gotcha for GUI git clients in README (U11).

**Test scenarios:**
- Covered by U10's meta-suite (hooks can only be tested through real git operations in a real repo).
- Test expectation here: none — config only; U10 is its test.

**Verification:**
- `lefthook run pre-commit --all-files` and `lefthook run pre-push` pass on the clean tree; wall-clock for pre-commit on a small staged diff is ≤5s.

### U6. CI workflow — 7 checks + gate + ruleset

**Goal:** The authoritative gate tier: everything local re-runs in CI, one required check name.

**Requirements:** R2, R3

**Dependencies:** U3, U4 (U5 not required — CI invokes tools directly, not via lefthook)

**Files:**
- Create: `.github/workflows/ci.yml`, `.github/rulesets/main.json`

**Approach:**
- One workflow, `on: pull_request` + `push: main`, **no `paths:` filters**. Jobs (stable `name:`s): `lint`, `typecheck`, `architecture`, `tests-build`, `quality` (jscpd + changed-coverage vs PR base + complexity), `secrets` (gitleaks-action@v3, checkout `fetch-depth: 0`), `workflow-lint` (actionlint download-script + pip yamllint).
- `gate`: `needs:` all 7, `if: always()`, fails unless every `needs.*.result == 'success'`.
- OSV-Scanner job via reusable-workflow call: `jobs.osv.uses: google/osv-scanner-action/.github/workflows/osv-scanner-reusable-pr.yml@v2.3.8` with `scan-args: --lockfile=./pnpm-lock.yaml` and permissions `actions: read`, `security-events: write`, `contents: read`. Included in `gate`'s `needs` (a `uses:` job is a legal dependency). Known constraint to verify on first fork PR: `security-events: write` is restricted in fork contexts — fallback per Key Technical Decisions is advisory-in-CI with pre-push staying blocking.
- `jdx/mise-action` for binary parity with local hooks.
- All third-party actions (gitleaks-action, mise-action, the osv-scanner reusable workflow) are pinned to **full commit SHAs** with a version comment, not mutable tags — a re-tagged upstream release would otherwise run in CI with secrets, contradicting the template's zero-supply-chain-surface posture. Applies to U8's workflows too; first-party `actions/*` may stay on major tags.
- `main.json` ruleset: target branch `~DEFAULT_BRANCH`, required status check `gate` with `integration_id: 15368`, `strict_required_status_checks_policy: true`.

**Test scenarios:**
- Integration (in U10's CI matrix): each bad-input class fails its specific job and therefore `gate`.
- Happy path: clean tree → all 7 green, `gate` green.
- Error path: one job cancelled/skipped → `gate` fails (the `if: always()` + result-check contract).

**Verification:**
- actionlint passes on the workflow; a deliberately broken PR in the template repo shows the failing job and a red `gate`.

### U7. Deploy workflow — Vercel via CI only

**Goal:** Preview on PR, production on merge, no other path.

**Requirements:** R4

**Dependencies:** U2, U6

**Files:**
- Create: `.github/workflows/deploy.yml`
- Modify: `services/example-service/vercel.json` (created in U2 — confirm `git.deploymentEnabled: false` + any needed build config)

**Approach:**
- Preview job (`pull_request`): `vercel pull --environment=preview` → `build` → `deploy --prebuilt` with `--cwd services/example-service`; capture stdout URL; post/update a sticky PR comment via `gh pr comment` (Vercel bot is silent on CLI deploys). Concurrency `preview-${{ github.ref }}`, cancel-in-progress. Guard with `if: github.event_name == 'pull_request'` — deploy.yml carries two triggers, and unguarded, every `workflow_run` completion on main would start a pointless preview that fails at `gh pr comment` with no PR in context.
- Production job: deploy.yml triggers on `workflow_run` — the CI workflow completing with `conclusion: success` on `main` (see Key Technical Decisions: structural "no green, no deploy" even for ruleset-bypassing pushes). Guard the job with an explicit conclusion check, and check out `${{ github.event.workflow_run.head_sha }}` explicitly so the built artifact is exactly the commit CI verified — a default checkout takes the branch tip at event time, which can race ahead of the verified commit if someone bypass-pushes while the deploy starts. `--prod` variants of pull/build/deploy; concurrency `production-deploy`, no cancel-in-progress (merges queue in order); GitHub Environment `production` holding `VERCEL_TOKEN` — environment protection rules give a free human-approval gate later without workflow changes.
- Secrets: `VERCEL_TOKEN` (secret), `VERCEL_ORG_ID` / `VERCEL_PROJECT_ID` (vars). Vercel CLI pinned as devDependency; run `pnpm vercel …`.

**Test scenarios:**
- Test expectation: none automatable in the template without a live Vercel project — verification is the documented E2E pass (R4) performed once against a real project; actionlint covers static validity.

**Verification:**
- With real secrets set: PR gets a preview URL comment; merge to `main` produces a production deploy; pushing with auto-deploy accidentally re-enabled produces **no** duplicate deploy (`deploymentEnabled: false` honored).

### U8. Nightly workflow — deep scans and issue automation

**Goal:** Semgrep + per-package incremental Stryker + license audit on schedule; failures become one deduplicated issue.

**Requirements:** R5, R6

**Dependencies:** U2, U6

**Files:**
- Create: `.github/workflows/nightly.yml`, `scripts/nightly-issue.sh`
- Create: `services/example-service/stryker.config.json`, `packages/contracts/stryker.config.json`

**Approach:**
- `schedule:` cron + `workflow_dispatch` with a `force_fail` input (makes the issue path testable on demand).
- Semgrep job: `container: semgrep/semgrep`, pinned registry configs (`p/typescript`, `p/security-audit`) + `--error`; no login/token.
- Stryker: per-package configs (`testRunner: vitest`, `thresholds: {high: 80, low: 60, break: 70}`, `incremental: true`); `actions/cache` on `reports/stryker-incremental.json`; first-Sunday-of-month run passes `--force` (incremental can't see dependency/config changes).
- Licenses: `license-checker-rseidelsohn --onlyAllow "MIT;Apache-2.0;ISC;BSD-2-Clause;BSD-3-Clause" --excludePrivatePackages`.
- Final job `if: failure()`: `scripts/nightly-issue.sh` — `gh issue list --label nightly-failure --state open` → comment run-URL + per-gate summary on the open issue, else `gh issue create --label nightly-failure`. Permissions `issues: write`; `GH_TOKEN: ${{ github.token }}`.

**Test scenarios:**
- Happy path: `workflow_dispatch` clean run → all jobs green, no issue.
- Error path: `force_fail` run with no open nightly issue → new labeled issue containing the run URL.
- Error path: `force_fail` again with the issue open → comment appended, no second issue (label dedupe).
- Edge case: `nightly-issue.sh` under `set -euo pipefail` handles zero-open-issues without aborting (shellcheck-clean, tested via U10's script checks).

**Verification:**
- Dispatch runs demonstrate both paths; incremental cache hit visible in the second Stryker run's log.

### U9. Bootstrap script

**Goal:** One command closes the gap the template mechanism leaves: repo settings.

**Requirements:** R1, R3

**Dependencies:** U6 (ruleset JSON exists)

**Files:**
- Create: `scripts/setup.sh`

**Approach:**
- Steps: verify `gh auth status` + repo context → import `.github/rulesets/main.json` via `gh api repos/{owner}/{repo}/rulesets --method POST`; on 403/422 for a free private repo, print a clear message that required checks need a public repo or a paid plan (classic branch protection is equally paid-only on private repos — there is no free fallback), mark the step skipped with a warning, and continue → prompt for and `gh secret set` VERCEL_TOKEN, `gh variable set` ORG/PROJECT ids (skippable) → create `nightly-failure` label → `mise install`, `pnpm install`, `lefthook install`.
- Idempotent: re-running detects the existing ruleset/label and skips. ShellCheck-clean (it's inside its own gate).

**Test scenarios:**
- Happy path: fresh clone + setup.sh → ruleset visible via `gh ruleset list`, hooks installed, label exists.
- Edge case: second run → no duplicate ruleset/label, exit 0.
- Error path: no `gh` auth → clear message, non-zero exit, nothing half-applied before the check.
- Error path: free private repo → protection step skipped with a clear explanation (no free fallback exists); remaining setup steps still complete.

**Verification:**
- Run against a scratch GitHub repo exercises all four scenarios.

### U10. Gate self-verification suite

**Goal:** Executable proof the gates reject what they claim to (R2 made code).

**Requirements:** R2

**Dependencies:** U5, U6

**Files:**
- Create: `tests/gates/verify-gates.sh` (or `.test.ts` driving it), CI job `self-verify` appended to `.github/workflows/ci.yml` and added to `gate`'s `needs`

**Approach:**
- `mktemp -d` → `git init` → copy template tree (checkout-index pattern) → `pnpm install && lefthook install`.
- Negative matrix through **real `git commit`** (catches install/PATH/config wiring, not just tool flags): runtime-generated fake AWS key (`AKIA` + random) → pre-commit rejects; ESLint-warning file → rejects; cross-service import → rejects. Pre-push matrix via `lefthook run pre-push` after committing an uncovered function **on a feature branch off the temp repo's initial commit** — on the default branch the coverage gate's base resolves to HEAD, the diff is empty, and the assertion would pass vacuously → rejects.
- Positive control: clean commit succeeds — catches gates so broken they reject everything.
- Same bad inputs run against the **CI job commands directly** (not via hooks) — proves the CI duplicates reject identically, since hooks are `--no-verify`-bypassable.
- Fake secrets generated at runtime only; nothing secret-shaped is ever written into the template tree.

**Execution note:** Test-first by nature — this unit IS the test layer; build the matrix before wiring it into `gate`.

**Test scenarios:**
- (The unit is itself the enumerated matrix above: 4 rejection cases + 1 positive control + CI-command parity.)

**Verification:**
- Suite passes locally and as the `self-verify` CI job; `gate` now needs 9 jobs (7 quality checks + OSV + self-verify).

### U11. Documentation

**Goal:** A clone is usable without this conversation.

**Requirements:** R1, R6

**Dependencies:** All prior units

**Files:**
- Create: `README.md`
- Modify: `CLAUDE.md` (sync commands/threshold locations), `SPEC.md` (status → v1 shipped)

**Approach:**
- README doubles as the product landing page: a one-paragraph pitch (the thesis — the quality bar is what makes AI speed possible), a mermaid tier diagram, CI + license badges (the self-verify badge literally means "the gates were tested against bad input"), then: quickstart (`Use this template` → `scripts/setup.sh`), tier table with what-runs-where, one table of every threshold and its file, the mutation-ratchet instruction (70→80), the database-per-service convention (convention only, not tooling-enforced — carried from SPEC), Vercel setup incl. disabling git auto-deploy and the org-repo `GITLEAKS_LICENSE` note, GUI-git-client PATH gotcha, documented limitations (no update propagation; branch protection needs a public repo or paid plan on private repos — setup.sh warns and skips).

**Test scenarios:**
- Test expectation: none — documentation; U9's fresh-clone verification doubles as the docs walkthrough test.

**Verification:**
- A fresh-eyes pass following only README reproduces acceptance criteria 1–3.

### U12. Productization

**Goal:** The repo is shippable as a public GitHub product, and every clone carries the docs its downstream users — human and agent — need.

**Requirements:** R7

**Dependencies:** U11

**Files:**
- Create: `LICENSE`, `AGENTS.md`, `SECURITY.md`, `CHANGELOG.md`, `docs/gate-failures.md`
- Modify: `CLAUDE.md`, `README.md`, `docs/maintaining.md` (exists — created during planning)

**Approach:**
- `LICENSE`: MIT.
- `AGENTS.md` at the repo root is the **downstream agent instructions** — since everything committed here gets cloned, the file ships into every project automatically. Content: run `pnpm check` before committing; never `--no-verify`; services import only `packages/contracts`; the threshold table and where each value lives; how to add a service (copy `services/example-service`); pointer to the gate-failure playbook. `CLAUDE.md` becomes a thin pointer to `AGENTS.md` so both Claude Code and AGENTS.md-reading tools pick it up; the template-authoring guidance lives in `docs/maintaining.md` (already created during planning — U12 verifies it stays consistent with the shipped file set and completes the CLAUDE.md pointer switch).
- `docs/gate-failures.md`: one table per gate — failure output → what it means → the sanctioned fix → the sanctioned override (e.g. `pnpm.auditConfig.ignoreCves`, `// Stryker disable` comments, the 70→80 mutation ratchet). This converts "the pipeline is fighting me" into "the pipeline told me what to do."
- `SECURITY.md`: reporting contact placeholder and a summary of the template's secrets-handling model.
- `CHANGELOG.md` (Keep a Changelog format) + semver git tags and GitHub releases; since there is no update propagation, releases are the only way downstream repos can know they're behind — record the template version in a `package.json` field so clones carry their provenance.
- Repo-metadata checklist (maintainer section, since GitHub settings don't clone): mark as **Template repository**, add topics (`template-repository`, `typescript`, `monorepo`, `ci-cd`, `quality-gates`, `ai-generated-code`), set a social-preview image, and keep one deliberately-broken demo PR open showing the red `gate` check as the live demo.

**Test scenarios:**
- Test expectation: none — documentation and repo metadata; the self-verify suite (U10) remains the executable proof that the failures the playbook documents actually occur.

**Verification:**
- A fresh clone contains LICENSE and AGENTS.md; a new agent session pointed at a clone can state the gate rules from AGENTS.md alone, without this repo's history.
- Every checklist item is actionable as written against a scratch GitHub repo.

---

## System-Wide Impact

- **Interaction graph:** lefthook config, CI jobs, and the self-verify suite must agree on tool invocations — U10 is the parity check; any gate command change must update all three.
- **Error propagation:** local gate failures print the failing tool's output directly; CI failures surface per-job; nightly failures funnel into one labeled issue.
- **State lifecycle risks:** Stryker incremental cache can go stale vs. dependency changes — monthly `--force` run resets it. setup.sh must stay idempotent.
- **Unchanged invariants:** SPEC.md remains the decision record; the plan implements v1.1 without reopening locked decisions.

---

## Risks & Dependencies

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|------------|
| Vitest 4 changed-file coverage edge cases (files missing from report) | Med | High (gate silently passes) | Explicit `coverage.include`; absent-file = 0% rule; U4 test-first |
| Pre-commit exceeds 5s as repos grow | Med | Med | Heavy gates already at pre-push; measure in U5 verification; README documents moving more gates back |
| gitleaks-action needs `GITLEAKS_LICENSE` on org repos | High for orgs | Med (CI secrets job fails) | Documented in README + setup.sh hint; personal repos unaffected |
| Branch protection unavailable on free private repos (rulesets and classic are both paid-only there) | Med | Med | setup.sh detects, warns, and skips; README documents the limitation (U9, U11) |
| Stryker runtime too long even incrementally | Low-Med | Low (nightly only) | perTest coverage analysis, per-package split, incremental cache; measured in U8 |
| OSV reusable workflow fails on fork PRs (`security-events: write` restricted) | Med | Low | Ships in `gate`'s `needs`; documented fallback demotes to advisory; pre-push OSV scan still blocks locally |
| Tool drift invalidates pinned versions/configs | Certain, slowly | Med | Everything exact-pinned (mise + package.json); README documents the upgrade path |

---

## Sources & References

- **Origin document:** [SPEC.md](SPEC.md) (v1.1) — with [CLAUDE.md](CLAUDE.md) conventions
- Research: framework-docs sweep (live registry/API verification, 2026-07-17) and best-practices sweep — key sources: lefthook repo & docs, gitleaks README, Stryker incremental docs, Vitest 4 migration notes, Vercel + GitHub Actions KB, GitHub rulesets docs, mise registry, jscpd v5 notes, license-checker fork discussions
