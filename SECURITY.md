# Security Policy

## Reporting a vulnerability

<!-- Downstream projects: replace this placeholder with your own contact
     (e.g. a security@ address, or GitHub's private vulnerability reporting
     for this repo) before publishing. -->

Report suspected vulnerabilities to: `security@example.com` (placeholder — update after cloning).

Please do not open a public issue for a suspected vulnerability. Include reproduction steps and the affected commit/version where possible.

## Secrets-handling model

Deploy Shield's gates are built around the assumption that a secret will eventually be typed or generated somewhere in the repo — the pipeline's job is to catch it before it reaches a remote.

- **gitleaks runs at pre-commit and in CI.** Pre-commit (`lefthook.yml`) scans staged changes on every local commit (`gitleaks git --pre-commit --redact --staged`); the CI `secrets` job (`.github/workflows/ci.yml`) re-scans the full PR diff history. Both are the same tool at different scopes, matching the three-surface lockstep rule in `docs/maintaining.md`.
- **Never commit secret-shaped strings, even fake ones.** GitHub push protection and gitleaks both pattern-match on the *shape* of a secret, not just known values — a fixture that merely looks like an AWS key or a token will be flagged the same as a real one. The self-verification suite (`tests/gates/verify-gates.sh`) generates its fake secrets at runtime, inside a throwaway temp repo, and never writes them into the template tree itself.
- **`VERCEL_TOKEN` lives only in GitHub Actions secrets** (`.github/workflows/deploy.yml`), never in a config file, environment file, or committed script. `VERCEL_ORG_ID` / `VERCEL_PROJECT_ID` are non-secret repo variables.
- **`GITHUB_TOKEN` is scoped per job to the minimum permissions it needs** — every workflow in `.github/workflows/` sets an explicit top-level `permissions: contents: read`, and individual jobs that need more (e.g. `secrets`'s `pull-requests: write`, `report-failure`'s `issues: write`) declare that need at the job level rather than inheriting broad defaults.
- **Third-party GitHub Actions are pinned to full commit SHAs**, not mutable version tags, so a re-tagged upstream release can't silently run in CI with repo secrets.
- **Org-owned repos** need a `GITLEAKS_LICENSE` secret for `gitleaks-action` to run in CI; personal-account repos are exempt. See `README.md` → Vercel setup / gitleaks note.
