# AGENTS.md

Instructions for any agent working in a repository cloned from the Deploy Shield template. This file ships into every clone — read it with no other context.

## Before committing

Run:

```bash
pnpm check
```

This runs everything the pre-push hook runs: tests, typecheck, jscpd, changed-file coverage, `pnpm audit`, and OSV-Scanner. Fix failures before committing; don't route around them.

## Never use `--no-verify`

CI re-runs every local gate independently — bypassing hooks locally only defers the failure to a PR, where the single required check is the `gate` aggregator job (`.github/workflows/ci.yml`), which needs all quality jobs to succeed. `--no-verify` buys nothing but a slower feedback loop.

## Architecture boundary

Services import `@deploy-shield/contracts` and their own code — nothing else outside themselves. Importing another `services/*` package, or any `packages/*` other than `contracts`, is a hard error enforced by `dependency-cruiser` (`.dependency-cruiser.cjs`), checked at pre-commit (staged files) and in CI's `architecture` job (whole tree). There is no sanctioned override for this rule — see `docs/gate-failures.md`.

## Thresholds and where they live

| Threshold | Value | File |
|---|---|---|
| Changed-file coverage | 85% | `package.json` → `deployShield.changedFileCoverage` |
| Duplication | <3% | `.jscpd.json` → `threshold` |
| Mutation score (visible bar) | `high: 80` | `packages/contracts/stryker.config.json`, `services/example-service/stryker.config.json` → `thresholds.high` |
| Mutation score (failure line) | `break: 70` | same files → `thresholds.break` (ratchets to 80 once stable) |
| Lint warnings | 0 | `lint` script in `package.json` (`eslint . --max-warnings 0`) |
| Dependency audit severity | `high` | `lefthook.yml` pre-push `audit` job (`pnpm audit --audit-level high`) |
| License allowlist | see `nightly.yml` | `.github/workflows/nightly.yml` → `licenses` job, `ALLOWED_LICENSES` env |

## Adding a service

Copy `services/example-service` to `services/<name>`. Add a `stryker.config.json` and a `vitest.config.ts` matching the ones already in `services/example-service` — the root Vitest config discovers workspaces via `test.projects`, and Stryker has no workspace orchestration, so every package needs its own config.

## Where the gates live

- `lefthook.yml` — local pre-commit and pre-push hooks.
- `.github/workflows/ci.yml` — the authoritative CI re-run of every local gate, plus the `gate` aggregator (the one required check) and the `self-verify` job.
- `.github/workflows/nightly.yml` — Semgrep, per-package Stryker mutation testing, license allowlist audit.
- `tests/gates/verify-gates.sh` — the self-verification suite; proves the above actually reject bad input.

Any change to a gate's command, threshold, or scope must update all three surfaces (`lefthook.yml`, `ci.yml`, `tests/gates/`) in the same commit — see `docs/maintaining.md` if you're changing the template itself rather than using it.

## When a gate goes red

See `docs/gate-failures.md` for the per-gate playbook: what the failure means, the sanctioned fix, and the sanctioned override (if one exists).
