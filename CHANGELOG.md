# Changelog

All notable changes to this project are documented in this file. The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres to [Semantic Versioning](https://semver.org/).

Releases are the **only** update signal for downstream clones — there is no mechanism that propagates template changes into a repo that already ran "Use this template". Check this file (or the GitHub Releases page) against your clone's `package.json` → `deployShield.templateVersion` to see whether you're behind.

## [1.4.0] - 2026-07-19

### Added

- `scripts/smoke-test.sh` — the post-deploy check, extracted from the workflow so both deploy jobs share one implementation that ShellCheck and the playbook can cover. Probes `GET /api/health` and `POST /api/echo`, retries with a bounded `--max-time`, and distinguishes a timeout (`000`) from a protection wall (`401`/`302`) in its failure message.
- **Previews are smoke-tested too.** With a Protection Bypass for Automation secret in `VERCEL_AUTOMATION_BYPASS_SECRET`, CI can reach a deployment that stays private to everyone else — so a broken build is caught on the PR rather than after it merges.

### Changed

- **Preview** deployments are private; the smoke test authenticates with the bypass header rather than the service being world-readable. Note that **production deployments cannot be protected on Vercel's free plan** — `deploymentType: "all"` is rejected with `428 invalid_sso_protection` ("Vercel Authentication is not available on your plan for production deployments"), so `all_except_custom_domains` is the ceiling and it covers previews only. Treat anything a free-plan project deploys to production as public.

## [1.3.1] - 2026-07-19

### Fixed

- **Vercel entrypoints use named HTTP-method exports.** They were bare `export default function handler(request: Request)`, which Vercel's Node.js runtime treats as the legacy `(req, res)` signature — the returned `Response` is discarded and the response is never ended, so every request hung until the 300s function timeout and returned 504. The runtime accepts a web-standard handler only as a named method export (`export function GET`) or `export default { fetch }`. This was masked until 1.3.0 because the module never loaded at all.
- **The smoke test caps each request with `curl --max-time`.** Without it the first run of the smoke test sat through two 300s function timeouts and hit the job's 15-minute limit — reporting `cancelled` instead of a failure. It now also exercises `POST /api/echo`, so a regression in either method export is caught.

## [1.3.0] - 2026-07-19

### Fixed

- **The example service now actually runs when deployed.** `packages/contracts` exported raw TypeScript (`exports` → `./src/index.ts`), which every local consumer tolerated because vitest transpiles and `tsc` only checks types — but Node cannot import `.ts`, so every deployed request failed with `ERR_MODULE_NOT_FOUND` and returned HTTP 500. The package now builds to `dist/` and exports the built output.

### Added

- **Post-deploy smoke test.** The production job requests `/api/health` and fails if it doesn't return 200. A deploy exiting 0 only proves the upload succeeded; nothing else in the four gate tiers ever executes the built artifact, which is exactly how a service that 500s on every request shipped green. Previews are excluded — they sit behind Vercel SSO unless the project configures Protection Bypass for Automation.
- `pnpm build` (root) builds all workspace packages; the deploy workflow runs it before invoking Vercel so the file tracer can follow `contracts` into `dist/`.

### Changed

- Typechecking and tests stay buildless: `tsconfig.base.json` maps the `@deploy-shield/contracts` specifier to source via `paths`, and the example service's `vitest.config.ts` mirrors it with `resolve.alias`. Keep those two and the package's `exports` in sync.

## [1.2.0] - 2026-07-19

### Fixed

- **Test files under `api/` no longer deploy as live endpoints.** Vercel compiles every file in that directory into its own serverless function, so a colocated `api/handlers.test.ts` was building into `handlers.test.func` and would have shipped as a publicly reachable route. The service's entrypoint tests moved to `src/`, and a `.vercelignore` now excludes `*.test.ts` as a second guard.
- **Deploys of a workspace-dependent service now work.** The Vercel CLI ran with `--cwd <service>`, which resolves pnpm workspace symlinks relative to the git root but joins them onto the cwd — producing a doubled path (`services/example-service/services/example-service/node_modules/…`) and failing every deploy. Both jobs now run the CLI from the repo root.

### Changed

- `scripts/setup.sh` sets the Vercel project's **Root Directory** (via the REST API — the CLI has no flag for it), which is what makes the repo-root deploy above resolve to the right service. Its non-interactive branch prints the equivalent `curl`.
- README documents where the Vercel org/project IDs come from, the Root Directory requirement, and the never-put-tests-in-`api/` rule.

### Notes

- Both fixes were found by the first live deploy against a real Vercel project — neither was reachable by any local gate, since no gate exercises Vercel's builder.

## [1.1.0] - 2026-07-19

### Added

- Gate self-verification suite expanded from 4 to 9 negatively-tested gates: new scenarios prove typecheck (pure type error at pre-push), prettier (misformatted file at pre-commit), and shellcheck/yamllint/actionlint (one bad fixture each) all still reject bad input. jscpd, audit/OSV, and the nightly gates remain deliberately untested negatively — see `docs/maintaining.md` for the reasoning.

### Fixed

- Preview-deploy sticky comment failure no longer fails the `preview` job when the deploy itself succeeded — it degrades to a `::warning` annotation naming the likely token-permission cause and the preview URL.
- `scripts/setup.sh` no longer aborts mid-run (skipping the remaining steps and the summary) when Ctrl-D is pressed at a Vercel prompt — EOF now means "skip this prompt", matching blank Enter.

## [1.0.0] - 2026-07-17

### Added

- pnpm/TypeScript monorepo skeleton: `packages/contracts` (shared types, zod schemas, ports, seed data) and `services/example-service` (a minimal, Vercel-deployable HTTP service), enforced as the only allowed cross-package import via `dependency-cruiser`.
- Four-tier quality gate pipeline: lefthook pre-commit (~3-5s: gitleaks, ESLint, Prettier, dependency-cruiser, shellcheck/yamllint/actionlint), lefthook pre-push (full tests, typecheck, jscpd, changed-file coverage, `pnpm audit` + OSV-Scanner), a 9-job CI workflow behind a single `gate` aggregator check, and a nightly workflow (Semgrep, per-package incremental Stryker mutation testing, license allowlist audit) that auto-files a deduplicated GitHub issue on failure.
- CI-only Vercel deploy path: PR previews on `pull_request`, production deploys gated on a green CI run on `main` via `workflow_run` — auto-deploy is disabled everywhere else, and `vercel.json`'s `git.deploymentEnabled: false` keeps it off even if the dashboard integration is reconnected.
- `scripts/setup.sh`: one-shot bootstrap for a fresh clone — imports the branch-protection ruleset, prompts for Vercel secrets, creates the nightly-failure label, and installs the local toolchain.
- `tests/gates/verify-gates.sh`: an executable self-verification suite proving the gates reject bad input (fake secret, lint warning, cross-service import, uncovered change) and that a clean commit still succeeds; runs as CI's `self-verify` job.
- Productization: `LICENSE` (MIT), `AGENTS.md` (downstream agent instructions), `docs/gate-failures.md` (per-gate playbook), `SECURITY.md`, and this changelog.

### Notes

- See `SPEC.md` → "As-shipped revisions" for the points where the shipped implementation diverged from the original spec text (Vercel CLI invocation, TypeScript pin, `@types/node` per package, the nightly license allowlist, and the `qs` override as a worked OSV-gate example).
