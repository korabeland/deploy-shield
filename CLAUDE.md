# Deploy Shield

A reusable GitHub **template repository** for TypeScript monorepos of AI-generated code: layered quality gates (pre-commit → pre-push → CI → nightly) where CI is the only path to production. Full design in [SPEC.md](SPEC.md) — read it before making structural changes; its "Locked decisions" table is authoritative.

## Ground rules

- This repo IS the template. Everything committed here gets cloned into downstream projects — keep it generic, no project-specific values. Repo-specific values (Vercel IDs, tokens) belong in documented secrets/placeholders.
- Thresholds (85% changed-file coverage, <3% duplication, 80% mutation, zero warnings) live in visible config files, never hardcoded in scripts.
- Do not add paid/SaaS dependencies. The zero-account, clone-and-go property is a core feature (this is why SonarCloud and CodeQL were rejected — see SPEC.md).
- The template must pass its own gates: every commit here goes through the same lefthook hooks the template ships.

## Stack

- **pnpm** workspaces; **Vitest** (+ v8 coverage); **lefthook** for git hooks; **TypeScript strict** everywhere.
- Monorepo layout: `packages/contracts` (shared types/zod/ports — the only cross-service import allowed), `services/*` (isolated services), enforced by **dependency-cruiser**.
- CI: **GitHub Actions**. Deploy: **Vercel via CI** (`vercel build` + `vercel deploy --prebuilt`); git auto-deploy stays OFF.
- Nightly tier: Semgrep, Stryker (80%), license-checker — failures auto-file a labeled GitHub issue.

## Commands

- `pnpm install && lefthook install` — bootstrap a clone
- `pnpm test` — full test suite (Vitest, all workspaces)
- `pnpm typecheck` — repo-wide `tsc --noEmit`
- `pnpm lint` — ESLint `--max-warnings 0` + Prettier check
- `pnpm check` — everything the pre-push hook runs

(Keep this list in sync with `package.json` scripts as they are created.)

## Conventions

- Conventional commits (`feat:`, `fix:`, `chore:`, ...). Feature branches + PRs; the 7 CI checks are all required.
- Tests live next to the code they test within each workspace; the changed-file coverage gate (≥85%) applies to every touched source file.
- New services copy `services/example-service`; they may import `packages/contracts` and nothing else outside themselves.
