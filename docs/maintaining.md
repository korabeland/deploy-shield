# Maintaining Deploy Shield

Guidance for working on the **template itself**. If you're in a repo *cloned from* this template, this file isn't for you — see `AGENTS.md` for the downstream rules.

## Documentation map

| File | Audience | Purpose |
|---|---|---|
| `SPEC.md` | Maintainers | Decision record — the "Locked decisions" table is authoritative |
| `docs/plans/` | Maintainers | Implementation plans (built via ce-plan; executed via ce-work) |
| `docs/maintaining.md` | Maintainers | This file — how to change the template safely |
| `AGENTS.md` | Downstream (humans + agents) | Gate rules, thresholds, how to add a service |
| `docs/gate-failures.md` | Downstream | Per-gate playbook: failure → meaning → sanctioned fix |
| `CLAUDE.md` | Downstream | Thin pointer to `AGENTS.md` (from v1 ship onward) |
| `README.md` | Everyone | Product landing page + quickstart |

## Ground rules

- **This repo IS the template.** Everything committed here gets cloned into downstream projects. Keep all content generic — repo-specific values (Vercel IDs, tokens, org names) exist only as documented secrets or placeholders.
- **SPEC.md is the decision record.** Don't reverse a locked decision in code without updating SPEC.md first; the rejected-alternatives column exists so decisions aren't accidentally relitigated.
- **No paid or SaaS dependencies.** Zero-account, clone-and-go is a core product feature (it's why SonarCloud and CodeQL were rejected). A change that adds a required account, token, or paid tier for the default path is a product change, not a tooling change.
- **Thresholds live in visible config files** (coverage 85, duplication 3, mutation high 80 / break 70), never hardcoded in scripts. If you add a gate, its threshold follows the same rule.
- **The template must pass its own gates.** Every commit here runs the same lefthook hooks the template ships.

## The three-surface lockstep rule

Every gate is defined in up to three places that must agree:

1. `lefthook.yml` (local hooks)
2. `.github/workflows/ci.yml` (the authoritative CI re-run)
3. `tests/gates/` (the self-verification suite proving the gate rejects bad input)

Any change to a gate's command, threshold, or scope updates all three in the same commit. The self-verify CI job is the regression net — if it goes red after your change, the gates and their tests have drifted apart.

**Self-verify's coverage is intentionally partial.** The suite proves nine gates reject bad input — fake secret (gitleaks), ESLint violation, cross-service import (dependency-cruiser), uncovered change (changed-coverage), type error (typecheck), misformatted file (prettier), and one bad fixture each for shellcheck, yamllint, and actionlint — plus a clean-commit positive control. Three classes remain deliberately untested negatively: **jscpd**, because its threshold is a repo-wide ratio and a fixed duplication fixture silently loses potency as the repo grows (the negative test would rot exactly where it's meant to protect); **audit/OSV**, because a negative test needs a real vulnerable dependency in the lockfile plus network access; and the **nightly gates** (semgrep, mutation, licenses), which are too heavyweight for a per-PR suite. If you weaken one of those, nothing but code review catches it.

## Shared packages must ship built output

`packages/contracts` builds to `dist/` and its `exports` point there — never at `src/*.ts`. Node cannot import raw TypeScript, so a package exporting `.ts` appears to work everywhere locally (vitest transpiles, `tsc` only checks types) and then fails at runtime the moment it is deployed. This template shipped exactly that bug in v1.0–v1.2; every request returned HTTP 500 while all four gate tiers stayed green.

Three places encode the same specifier and must stay in sync when you add a shared package:

1. the package's `exports` → built output (what the deployed lambda loads)
2. `tsconfig.base.json` → `paths` → source (so typechecking needs no build)
3. the consuming service's `vitest.config.ts` → `resolve.alias` → source (so tests need no build)

The deploy workflow runs `pnpm build` before invoking Vercel, because Vercel's file tracer can only follow the import once `dist/` exists.

## Version pinning and upgrades

- All tools are exact-pinned: npm devDependencies in `package.json`, non-npm binaries in `mise.toml`.
- Upgrade flow: bump the pin → run the full local gates → run the self-verify suite → note the bump in `CHANGELOG.md`. Watch for the known drift traps documented in SPEC.md's dependency table (deprecated subcommands, renamed actions, abandoned packages).
- Third-party GitHub Actions are pinned to full commit SHAs with a version comment. When bumping, update the SHA and the comment together.

## Releases

- Semver tags + GitHub releases, with a `CHANGELOG.md` entry (Keep a Changelog format) per release.
- Releases are the **only** update signal downstream — there is no propagation mechanism. Breaking changes to gate behavior or repo layout are major versions.
- The template version is recorded in a `package.json` field so clones carry their provenance.

## Repo metadata (not cloneable — re-check after settings changes)

- Repository marked as **Template repository**
- Topics: `template-repository`, `typescript`, `monorepo`, `ci-cd`, `quality-gates`, `ai-generated-code`
- Social-preview image set
- One deliberately-broken demo PR kept open (fake secret + cross-service import) showing the red `gate` check — the live demo
