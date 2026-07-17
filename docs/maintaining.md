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

**Self-verify's coverage is intentionally partial.** The suite proves the four SPEC acceptance classes reject bad input (fake secret, lint violation, cross-service import, uncovered change) plus a clean-commit positive control. The other gates (prettier, typecheck, jscpd, audit, osv, shellcheck/yamllint/actionlint) run for real in CI and pre-push but have **no negative self-test** — a green self-verify is not proof that every gate rejects bad input. Expanding the matrix is a deliberate scope decision, not a bug fix; if you weaken one of the uncovered gates, nothing but code review catches it.

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
