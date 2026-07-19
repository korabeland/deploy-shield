# Gate failure playbook

For every gate: what a failure means, the sanctioned fix, and the sanctioned override (if one exists). If no override is listed, there isn't one — the fix is the only path.

> **If a hook reports a tool "missing — run `mise install`" even though `mise install` succeeded:** the shell (or GUI git client) launching the hook doesn't have mise's shims on PATH. Run `eval "$(mise activate zsh)"` (or the equivalent for your shell) and add it to your shell rc; for GUI clients, add `~/.local/share/mise/shims` to the PATH they launch with. This applies to every mise-managed gate below (gitleaks, shellcheck, yamllint, actionlint, osv-scanner).

## gitleaks (secret scanning)

- **Runs:** pre-commit (`gitleaks git --pre-commit --redact --staged`), CI `secrets` job (full-history diff via `gitleaks-action`).
- **Failure means:** a staged/pushed change contains something that matches a secret pattern.
- **Fix:** remove the secret from the change, and **rotate it** — it may already be in git history or on a remote. Don't just delete the line and recommit; the value is compromised the moment it's staged.
- **Override:** for a genuine false positive (a string that matches a secret pattern but isn't one), add a targeted rule to `.gitleaks.toml`'s allowlist, scoped as narrowly as possible (path + regex, not a blanket disable).

## ESLint zero-warnings

- **Runs:** pre-commit (`eslint --max-warnings 0 {staged_files}`), CI `lint` job (`eslint . --max-warnings 0`).
- **Failure means:** any lint warning or error on the touched files — `--max-warnings 0` treats warnings as failures, there's no soft tier.
- **Fix:** fix the code.
- **Override:** a targeted `// eslint-disable-next-line <rule>` with a justification comment on the same or preceding line. Never a blanket file-level disable, and never widen a rule in `eslint.config.mjs` to fit one function.

## Prettier

- **Runs:** pre-commit (`prettier --check {staged_files}`), CI `lint` job (`prettier --check .`).
- **Failure means:** formatting doesn't match `.prettierrc.json`.
- **Fix:** `pnpm exec prettier --write <files>` (or `pnpm exec prettier --write .`), then re-stage.
- **Override:** none needed — this gate is mechanical.

## dependency-cruiser (cross-service import)

- **Runs:** pre-commit (staged files), CI `architecture` job (`depcruise packages services`).
- **Failure means:** a `services/*` module imports another `services/*` module directly, or a `services/*` module imports a `packages/*` other than `contracts`.
- **Fix:** move the shared code into `packages/contracts` if it genuinely needs to be shared, or replace the direct import with an HTTP call against the other service's published contract.
- **Override:** **none.** This is the architecture, not a style preference — the boundary is what keeps services independently deployable and lets parallel agent fleets work without stepping on each other.

## jscpd duplication (>3%)

- **Runs:** pre-push (`jscpd .`), CI `quality` job.
- **Failure means:** repo-wide duplication ratio exceeded the threshold in `.jscpd.json`.
- **Fix:** extract the duplicated logic into a shared helper (in `packages/contracts` if it crosses a service boundary, otherwise local to the package).
- **Override:** genuinely unavoidable duplication (e.g. generated code, fixture data) can be excluded via `.jscpd.json`'s ignore patterns — scope the pattern to the specific files, not a broad glob.

## Changed-file coverage (<85%)

- **Runs:** pre-push (`vitest run --coverage && node scripts/changed-coverage.mjs`), CI `quality` job (against the PR base SHA).
- **Failure means:** at least one changed source file has statement coverage below 85% (a changed file **absent** from the coverage report counts as 0%).
- **Fix:** write tests for the changed file.
- **Override:** the threshold lives in `package.json` → `deployShield.changedFileCoverage` and is technically editable, but lowering it is a team decision, not something to change to unblock one PR — treat a proposed change to this value the same as any other architectural/quality-bar change.

## typecheck

- **Runs:** pre-push (`tsc --noEmit -p tsconfig.base.json`), CI `typecheck` job.
- **Failure means:** a type error under TypeScript strict mode (plus `noUncheckedIndexedAccess`, `exactOptionalPropertyTypes`, etc. — see `tsconfig.base.json`).
- **Fix:** fix the types.
- **Override:** none — an `any` cast or `@ts-expect-error` is a fix path only when the underlying type genuinely can't be expressed narrower, and should carry a comment explaining why.

## `pnpm audit --audit-level high`

- **Runs:** pre-push (`audit` job), also part of `pnpm check`.
- **Failure means:** a `high` or `critical` severity advisory exists in the dependency tree (low/moderate are intentionally not blocking — see `lefthook.yml`'s comment on this gate).
- **Fix:** upgrade the affected dependency (directly, or by bumping whatever pulls it in transitively).
- **Override:** `pnpm.auditConfig.ignoreCves` in `package.json`, with the specific CVE ID and an expiry/reason comment next to it — don't ignore an advisory permanently without revisiting it.

## OSV-Scanner

- **Runs:** pre-push (`osv-scanner scan --lockfile=pnpm-lock.yaml`), CI `osv` job (reusable-workflow call, PR-only).
- **Failure means:** an OSV advisory matches something in `pnpm-lock.yaml` — this can catch things `pnpm audit` doesn't and vice versa, which is why both gates exist.
- **Fix:** upgrade the dependency. The repo's own `pnpm.overrides.qs: ">=6.15.2"` in `package.json` is the real worked example — the unfiltered OSV-Scanner gate caught a live advisory on `qs` during this template's own self-verification, and a pnpm override was the fix, not an ignore.
- **Override:** an `osv-scanner.toml` with a per-ID entry under `IgnoredVulns`, each with a reason. Scope to the specific vulnerability ID, never a blanket ignore.

## Stryker mutation testing (`break: 70`)

- **Runs:** nightly `mutation` job (per-package matrix: `packages/contracts`, `services/example-service`).
- **Failure means:** the mutation score fell below `thresholds.break` in that package's `stryker.config.json` — surviving mutants indicate assertions that don't actually pin down behavior.
- **Fix:** kill the survivors with more precise assertions. Worked example from this template's own build: `services/example-service` went from 55% to 91% by asserting exact error response bodies and headers instead of just status codes — the looser assertions let several mutants survive undetected.
- **Override:** `// Stryker disable next-line` (or the equivalent block comment) with a reason, for mutants that are genuinely equivalent (behaviorally identical to the original, not just hard to kill). The threshold direction is a **ratchet up only** — move `break` from 70 toward `high`'s 80 once the score is stable; never lower it to make a red run green.

## Semgrep

- **Runs:** nightly `semgrep` job (`p/typescript` + `p/security-audit` registry rulesets, `--error`).
- **Failure means:** a SAST rule matched.
- **Fix:** fix the flagged pattern.
- **Override:** `// nosemgrep: <rule-id>` on the matched line, with a justification comment — never a bare `// nosemgrep`.

## ShellCheck

- **Runs:** pre-commit on staged `*.sh` files, CI `workflow-lint` job (`shellcheck scripts/*.sh tests/gates/*.sh`).
- **Failure means:** a shell script has a construct ShellCheck flags (quoting, unset variables, portability).
- **Fix:** fix the script — the finding's `SC` code links to a wiki page with the reasoning and the safe pattern.
- **Override:** a targeted `# shellcheck disable=SCxxxx` comment on the line above, with a justification comment. Never a file-wide disable directive.

## yamllint

- **Runs:** pre-commit on staged `*.yml`/`*.yaml` files, CI `workflow-lint` job (`yamllint .`).
- **Failure means:** a YAML file violates `.yamllint.yml` (line length >120, indentation, syntax).
- **Fix:** fix the YAML.
- **Override:** a targeted `# yamllint disable-line rule:<name>` comment, or — for a rule that's genuinely wrong for this repo — a conscious edit to `.yamllint.yml` with a comment explaining why.

## actionlint

- **Runs:** pre-commit on staged workflow files, CI `workflow-lint` job.
- **Failure means:** a GitHub Actions workflow has a real defect — bad expression syntax, unknown context field, shellcheck findings inside `run:` blocks, wrong input names for an action.
- **Fix:** fix the workflow. actionlint findings are almost always genuine bugs that would otherwise surface as broken CI runs.
- **Override:** none — there is no suppression mechanism, and that's fine: fix the workflow.

## self-verify (gate self-verification suite)

- **Runs:** CI `self-verify` job (`bash tests/gates/verify-gates.sh`); runnable locally the same way.
- **Failure means:** a *gate itself* regressed — one of the covered gates (gitleaks, ESLint, dependency-cruiser, changed-file coverage) stopped rejecting bad input, or a supposedly-clean commit stopped passing. This is almost never caused by your feature change directly; it's caused by changes to gate configs.
- **Fix:** the fix nearly always lives in `lefthook.yml`, `.github/workflows/ci.yml`, or `tests/gates/verify-gates.sh` together — any change to a gate command must update all three surfaces in the same commit (see AGENTS.md). Run the suite locally for the failing scenario's output.
- **Override:** none. A red self-verify means the safety net has a hole; nothing else merges through it.

## Post-deploy smoke test

- **Runs:** `scripts/smoke-test.sh` in both deploy jobs, after the deployment is created.
- **Failure means:** the deployment uploaded successfully but the service does not serve requests. Read the codes in the error line: `500` usually means a module failed to load (a runtime dependency missing from the lambda); `000` means the request timed out, which is what a handler in the wrong export shape does — it never ends the response, so the platform kills it at 300s; `401`/`302` means the deployment is protected and `VERCEL_AUTOMATION_BYPASS_SECRET` is missing or stale.
- **Fix:** depends on the code above. For `500`, check that shared workspace packages export **built** output and that `pnpm build` runs before the Vercel CLI. For `000`, check the `api/` entrypoints use named HTTP-method exports. For `401`, regenerate the bypass secret and update the repo secret.
- **Override:** **none.** This is the only check in the entire pipeline that executes the deployed artifact — every other gate reasons about source. Disabling it means shipping unverified deployments, which is precisely how this template shipped a service that failed every request while all gates stayed green.

## License allowlist

- **Runs:** nightly `licenses` job (`license-checker-rseidelsohn --onlyAllow "$ALLOWED_LICENSES" --excludePrivatePackages --summary`).
- **Failure means:** a dependency (direct or transitive) carries a license not in the allowlist defined in `.github/workflows/nightly.yml`'s `ALLOWED_LICENSES` env.
- **Fix:** replace the dependency with one under an allowed license.
- **Override:** extend the allowlist in `nightly.yml` consciously — it already carries more than the base five (`MIT;Apache-2.0;ISC;BSD-2-Clause;BSD-3-Clause`) to cover real transitive dev-tooling licenses (`BlueOak-1.0.0`, `0BSD`, `MPL-2.0`, `CC-BY-4.0`, `CC-BY-3.0`, `CC0-1.0`, `MIT AND CC-BY-3.0`) — see the comment above that job for what pulls each one in. Alternatively, scope the scan with `--production` to exclude dev-only dependencies from the audit entirely if the flagged package never ships.
