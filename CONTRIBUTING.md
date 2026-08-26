# Contributing to Kern

Thanks for your interest in Kern — an open-source, self-hostable all-in-one work platform (issues & projects, chat, docs & drive, HR & recruiting, CRM, automation, mail, calls, AI).

## Ways to contribute
- **Bugs & ideas** — open an issue with the matching template.
- **Code** — pick an issue labeled `good first issue` / `help wanted`, or propose something in an issue first for larger changes.
- **Modules** — Kern is modular; third-party modules follow the same package shape as first-party ones (see the `modules` repo, `packages/_template`).
- **Docs & translations** — the docs site lives in the `docs` repo; UI translations (en/fa/ar/de and more) live with each package's messages.

## Development setup
```bash
git clone https://github.com/KernAIO/app && cd app
pnpm setup      # clones all repos into ./repos and installs (pnpm links @kernhq/*)
pnpm infra      # Postgres 18 · NATS · Valkey · MinIO · Mailpit (docker compose)
pnpm dev        # runs app + services with hot reload
```
Requirements: Node 24, pnpm 10, Docker. Each repo also works standalone with published `@kernhq/*` packages.

## Pull requests
1. Fork/branch from `main`; keep PRs focused and reasonably small.
2. Conventional Commits (`feat: …`, `fix: …`); clear PR description with the issue linked.
3. `pnpm typecheck && pnpm lint && pnpm test && pnpm build` must pass; add tests for behavior you add or fix.
4. Changes to published packages (`kernel`, `modules`) need a changeset (`pnpm changeset`).
5. By opening a PR you accept the [CLA](./CLA.md). Please also read our [Code of Conduct](./CODE_OF_CONDUCT.md).

## Project conventions (short version)
- TypeScript strict, ESM, Biome formatting (CI enforces it).
- API surface is contract-first (Zod + oRPC → REST/OpenAPI); modules own their Postgres schema (`mod_<id>`) with `workspace_id` + row-level security on tenant tables; cross-module access only through `kernel.call()` and events.
- UI: Svelte 5 + Tailwind v4, design tokens from `app/DESIGN.md`, i18n via Paraglide, RTL and dark mode are first-class.

## Continuous integration

The shared `@kernhq/*` packages are published to npm from the `kernel` and `modules` repositories, so
anyone can install them without credentials. CI in the other repositories installs them from npm,
which is why a change to a contract lands and publishes before its consumers are updated.

## Security
Please report vulnerabilities privately — see [SECURITY.md](./SECURITY.md). Do not open public issues for security problems.
