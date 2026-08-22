# CLAUDE.md — Kern project rules

Rules for anyone (human or AI agent) working on Kern repositories. These apply to every repo in the KernAIO org.

## We build in the open
The repositories are **public**, so every commit is visible the moment it is pushed:
- Never commit secrets, tokens, personal data, or machine-specific paths. Use `.env` (gitignored) + `.env.example`.
- Write READMEs, docs, and issue/PR text for external contributors, not for ourselves.
- Keep commit history clean and meaningful — it is part of what people judge the project by.
- Every repo carries LICENSE (AGPL-3.0), CLA.md, CODE_OF_CONDUCT.md, SECURITY.md, CONTRIBUTING.md.

## Git
- Author identity: `Navid Mirzaaghazadeh <mirzaaghazadeh@icloud.com>` (already set in each repo's local git config — plain `git commit` is correct; do not override with `-c`).
- **Do not add `Claude-Session:`, `Co-Authored-By: Claude`, "Generated with", or any AI trailer/branding to commit messages, PRs, or code comments.**
- Conventional Commits (`feat:`, `fix:`, `docs:`, `refactor:`, `test:`, `chore:`, with optional scope). Imperative mood, ≤ 72-char subject.
- Push to `origin main`. Never force-push. If `git pull --rebase` complains about unstaged files that aren't yours (parallel agents share worktrees), use `git -c rebase.autoStash=true pull --rebase`.

## Layout & workflow
- Umbrella dev workspace: `kern/` with sibling repos cloned under `kern/repos/<name>` (gitignored there). pnpm links all `@kernaio/*` packages via the umbrella workspace.
- Install dependencies ONLY via `kern/scripts/pnpm-install-locked.sh` (serialises pnpm at the umbrella root).
- Node 24 (`nvm use 24`), pnpm 10, TypeScript ~5.9, ESM/NodeNext, Biome for lint+format (run `pnpm exec biome check --write <paths>` before committing), Vitest.
- Contracts first: changes to `@kernaio/contracts` / module contracts land (and build) before their consumers.
- Modules own their data: Postgres schema `mod_<id>`, `workspace_id` + RLS on every tenant table, cross-module access only via `kernel.call()` and events. See `modules` repo `packages/_template`.
- Ports: app 5173 · core 4000 · chat 4100 · mail 4200 · collab 4300 · docs 4400.
- Dev DB on this machine: Homebrew Postgres 18 at `localhost:5432` (`kern`/`kern`); the compose Postgres listens on `${KERN_PG_PORT:-5432}` (5433 here).

## Quality bar
- `pnpm typecheck && pnpm lint && pnpm test && pnpm build` must pass before pushing.
- UI follows `app/DESIGN.md` (Ink/paper design system) and must work in RTL (fa/ar) and dark mode.
- All user-facing strings go through i18n (Paraglide) — no hardcoded English in components.
