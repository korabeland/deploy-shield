# Deploy Shield — Specification

**Status:** v1 shipped 2026-07-17 (decisions locked 2026-07-17; revised same day after external research — tier split, mutation thresholds, aggregator check, tool deprecations)

### As-shipped revisions

A handful of implementation details diverged from this document's original text once real tool versions and the template's own gates were in the loop. The "Locked decisions" table above is otherwise unchanged.

1. **Vercel CLI is not a `devDependency`.** Its transitive dependencies failed the template's own blocking audit gates, so `deploy.yml` invokes it via `npx --yes vercel@$VERCEL_CLI_VERSION`, pinned once at the top of the workflow, instead of installing it as a pinned devDependency.
2. **TypeScript is pinned at 6.0.3, not 7.x.** `typescript-eslint` 8.64.0 only supports TypeScript `<6.1.0`, and type-aware zero-warning linting is the core lint gate.
3. **`tsconfig.base.json` sets `"types": ["node"]` explicitly**, and every workspace package declares its own `@types/node` devDependency — TypeScript 6's automatic `@types` inclusion didn't resolve per-package under pnpm's workspace layout.
4. **The nightly license allowlist is broader than the five licenses named above.** It adds `BlueOak-1.0.0`, `0BSD`, `MPL-2.0`, `CC-BY-4.0`, `CC-BY-3.0`, `CC0-1.0`, and `MIT AND CC-BY-3.0` — all found only in the devDependency tree — and lives in `nightly.yml`'s `ALLOWED_LICENSES` env; `--production` scoping is documented as an alternative for downstream projects that would rather exclude dev tooling from the scan.
5. **`package.json` carries a `pnpm.overrides` entry for `qs` (`>=6.15.2`)** — a live OSV advisory the unfiltered OSV-Scanner gate caught during the template's own self-verification. Left in place deliberately as the worked example of the OSV gate doing its job (see `docs/gate-failures.md`).

## What it is

Deploy Shield is a reusable **GitHub template repository** for TypeScript monorepos of AI-generated code. Clone it (or `degit` it) into a new project and every path to production runs through layered quality gates. Auto-deploy is disabled everywhere; **CI is the only deployer**. No green, no deploy.

The thesis: AI agents meet whatever quality bar you set. The pipeline *is* the bar.

## What it is not

- Not an installable CLI (`npx deploy-shield init`) — that is a possible v2 once the template proves out.
- Not multi-language — TypeScript only in v1. A Python track (ruff, mypy, pytest-cov, mutmut, import-linter) is a candidate v2.
- Not a full platform — no auth or feature-flag infrastructure ships in v1.

## Locked decisions

| Decision | Choice | Rejected alternatives |
|---|---|---|
| Artifact | Template repo | Installable CLI (v2 candidate); single-project wiring; public product |
| Language | TypeScript monorepo only | TS + Python; language-agnostic core |
| CI platform | GitHub Actions | GitLab CI; CI-agnostic scripts |
| Deploy target | Vercel via CI | Docker + registry; pluggable stub; no deploy stage |
| Quality gate | Local tools (jscpd, ESLint complexity) | SonarCloud (onboarding friction, paid for private repos) |
| SAST | Semgrep | CodeQL (free only on public repos) |
| Thresholds | 85% changed-file coverage, <3% duplication, mutation `high`=80 / `break`=70 (documented ratchet to 80), zero lint warnings | Softer defaults; advisory-only mutation; hard break at 80 (red-balls on equivalent mutants day one) |
| Hook latency | Pre-commit stays ~3–5s: heavy gates (typecheck, jscpd, changed-file coverage) run at pre-push | All gates at commit (blows the "seconds" promise, invites `--no-verify`) |
| Required checks | Single aggregator `gate` job (needs all 7) is the one required check | Requiring all 7 names in the ruleset (renames silently orphan protection) |
| Binary tools | mise (`mise.toml`, version-pinned) for gitleaks, semgrep, osv-scanner, shellcheck, actionlint | Brewfile (no pinning, macOS-only); skip-if-missing (silently skips security gates); npm wrappers (third-party, laggy) |
| Architecture | Skeleton + boundary rules | Gates only; full platform (auth + flags) |
| Package manager | pnpm workspaces | npm workspaces; bun |
| Test runner | Vitest (+ v8 coverage) | Jest |
| Git hooks | lefthook (parallel) | husky + lint-staged; pre-commit (Python) |
| Nightly failure | Auto-file/update a labeled GitHub issue | Block subsequent deploys; notification only |

## The four gate tiers

### Tier 1 — Pre-commit (lefthook, parallel, target: 3–5s)

Runs on every local commit — fast gates only (community consensus: past ~10s, developers and agents reach for `--no-verify`, defeating the tier):

- **gitleaks** — secret scanning on staged changes (`gitleaks git --pre-commit --staged`; the older `protect` subcommand is deprecated)
- **ESLint** — `--max-warnings 0` on staged files (zero-warning policy)
- **Prettier** — format check on staged files
- **dependency-cruiser** — architecture boundaries on staged files; services physically cannot import each other
- **ShellCheck / yamllint / actionlint** — run only when matching files are staged

### Tier 2 — Pre-push (lefthook)

- Full test suite
- Repo-wide typecheck (`tsc --noEmit`, TypeScript strict)
- **jscpd** — repo-wide duplication capped under 3% (a repo-wide ratio; can't be computed from staged files alone)
- **Changed-file coverage** — ≥85% coverage on changed files (custom script over Vitest coverage JSON)
- Blocking dependency audit: `pnpm audit` + **OSV-Scanner**

### Tier 3 — CI on PR (GitHub Actions, 7 parallel required checks)

1. Lint (ESLint zero-warnings + Prettier)
2. Typecheck (repo-wide, strict)
3. Architecture (dependency-cruiser)
4. Tests + build (with coverage threshold)
5. Quality (jscpd duplication + ESLint complexity rules)
6. Secret scan (gitleaks full history diff)
7. YAML / workflow lint (yamllint + actionlint)

Two further jobs run alongside: an **OSV-Scanner** scan (reusable-workflow call) and the **gate self-verification suite**. An **aggregator job (`gate`)** needs all of the above and fails unless every one succeeded. The shipped ruleset (`.github/rulesets/main.json`) requires only `gate` — one stable check name, so adding or renaming checks never touches repo settings (a renamed required job silently orphans branch protection and blocks all merges). All jobs live in one always-running workflow — no `paths:` triggers, or skipped workflows leave PRs waiting forever on a check that never runs. Merge to `main` triggers the deploy job. There is no other path to production.

### Tier 4 — Nightly (scheduled workflow)

- **Semgrep** — SAST with pinned TS/JS registry rulesets (no login / no `SEMGREP_APP_TOKEN`)
- **Stryker** (vitest runner) — mutation testing per package, incremental mode with the incremental JSON cached between runs; `thresholds.high` = 80 (the visible bar), `thresholds.break` = 70 (the failure line), documented ratchet to 80 once stable; monthly forced full run to reset incremental drift
- **License compliance** — allowlist audit via license-checker-rseidelsohn (`--onlyAllow`)

A red nightly run opens (or updates, deduplicated by label) a GitHub issue via the `gh` CLI — no third-party issue actions — with the run URL and per-gate failure summary, so it's assignable to an agent next session. Deploys stay governed by the merge gates.

## Deploy stage

- GitHub Actions job runs `vercel build` then `vercel deploy --prebuilt` after all checks pass.
- Vercel's git auto-deploy integration must be **OFF** (documented setup step).
- PR branches get preview deploys via the same mechanism.
- Requires a `VERCEL_TOKEN` secret (plus `VERCEL_ORG_ID` / `VERCEL_PROJECT_ID`) per repo.
- Auto-deploy is disabled declaratively via `"git": { "deploymentEnabled": false }` in `vercel.json` — survives someone later connecting the git integration; the dashboard toggle alone does not.
- Since the Vercel bot doesn't comment on CLI deploys, the workflow posts the preview URL as a sticky PR comment itself.

## Bootstrap script (added to scope)

GitHub's template mechanism copies files, **not** repo settings — branch protection, secrets, and labels are manual per-repo work someone will skip. The template ships `scripts/setup.sh` that a fresh clone runs once:

- Imports `.github/rulesets/main.json` via `gh api repos/{owner}/{repo}/rulesets` (requires only the `gate` check)
- Prompts for and sets the three Vercel secrets via `gh secret set`
- Creates the nightly-failure label
- Runs `mise install`, `pnpm install`, `lefthook install`

## Gate self-verification (added to scope)

The template must prove its own gates work — otherwise gate regressions are invisible until a downstream project notices. A meta-test suite builds a throwaway git repo in a temp dir, installs the hooks, and asserts:

- A commit containing a runtime-generated fake secret is **rejected** (never commit secret-like fixtures — GitHub push protection and gitleaks would flag the template itself)
- A lint warning, a cross-service import, and an uncovered change are each rejected at the right tier
- A clean commit **succeeds** (catches gates so broken they reject everything)

Runs as a CI job in the template repo itself. This is acceptance criterion #2 made executable.

## Productization (added to scope)

The repo ships as a public GitHub product, and clones carry their own documentation:

- **MIT LICENSE** (a template without a license can't legally be used)
- **AGENTS.md** at root — downstream agent instructions, cloned into every project (gate rules, thresholds, how to add a service); CLAUDE.md becomes a pointer to it
- **docs/gate-failures.md** — per-gate playbook: failure → meaning → sanctioned fix → sanctioned override
- **SECURITY.md** and **CHANGELOG.md** + semver releases (releases are the only update signal, since there's no propagation mechanism)
- Repo-metadata checklist: Template-repository flag, topics, social preview, one open demo PR showing a red `gate`

## Monorepo skeleton (multi-agent architecture)

Designed so parallel agent fleets can build without stepping on each other:

- **`packages/contracts`** — single source of truth: shared types, zod schemas, port definitions, seed data. The only package services may import.
- **`services/example-service`** — one example service demonstrating the layout, its own tests, its own Vitest config.
- **dependency-cruiser rules** — services may import `contracts` and their own code; any cross-service import is a hard error. Integration between services happens over HTTP per the contracts.
- Database-per-service is a documented convention, not enforced tooling, in v1.

## Dependencies (all free, no paid SaaS)

| Tool | Role |
|---|---|
| pnpm | Package manager / workspaces |
| lefthook | Git hooks manager (parallel) |
| gitleaks | Secret scanning |
| ESLint + typescript-eslint | Lint, zero warnings, complexity rules |
| Prettier | Formatting |
| dependency-cruiser | Architecture boundary enforcement |
| jscpd | Copy-paste / duplication detection |
| Vitest + @vitest/coverage-v8 | Tests + coverage |
| Stryker (@stryker-mutator/vitest-runner) | Mutation testing |
| Semgrep | Nightly SAST (PyPI/Docker distribution — the npm `semgrep` package is a placeholder, never install it) |
| OSV-Scanner v2 | Dependency vulnerability audit (v2 CLI syntax differs from v1) |
| license-checker-rseidelsohn | License allowlist audit (original `license-checker` is abandoned; `license-checker-evergreen` is the fallback fork) |
| yamllint / actionlint / ShellCheck | Config & script linting |
| mise | Version-pinned installation of non-npm binaries (gitleaks, semgrep, osv-scanner, shellcheck, actionlint), locally and in CI via mise-action |
| Vercel CLI (pinned as devDependency) | Deploy from CI |

## Known trade-offs

- **No quality-trend dashboard** — the one real loss from dropping SonarCloud. Metrics exist per-run in CI logs/artifacts only.
- **Mutation testing at 80%** may need per-file tuning early; the threshold lives in visible config, not a buried constant.
- **Changed-file coverage** has no off-the-shelf tool — a small custom script over Vitest's `coverage-final.json` is the one piece of genuine glue code in this build.
- **Semgrep < CodeQL** in analysis depth, but works identically on private repos at zero cost.

## Acceptance criteria for v1

1. `scripts/setup.sh` (or `mise install && pnpm install && lefthook install`) in a fresh clone yields working pre-commit and pre-push gates.
2. The gate self-verification suite passes: fake secret, lint warning, cross-service import, and untested change are each rejected at the right tier; a clean commit succeeds. Runs in the template's own CI.
3. A PR shows the CI checks (7 quality checks, OSV scan, self-verify) plus the `gate` aggregator; the shipped ruleset requires `gate`, and `scripts/setup.sh` applies it.
4. Merge to `main` deploys to Vercel only when all checks are green; the example service is minimally deployable so this is testable end-to-end.
5. Nightly workflow runs on schedule and files/updates a deduplicated labeled issue on failure.
6. All thresholds (coverage, duplication, mutation high/break) are editable in one obvious config location.
7. A fresh clone contains LICENSE, AGENTS.md, and the gate-failure playbook; an agent session in a clone can state the gate rules from AGENTS.md alone.
