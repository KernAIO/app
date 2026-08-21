<p align="center"><strong>Kern</strong> — the open-source all-in-one work platform.</p>
<p align="center">Issues & projects · Chat · Docs & Drive · HR & Recruiting · CRM · Automation · Mail · Calls · AI — one app, many workspaces.</p>

> Status: **pre-release (building in private)**. Target v1.0 — Q4 2026.

## Self-host (Docker)

```bash
curl -fsSL https://raw.githubusercontent.com/KernALO/kern/main/selfhost/install.sh | bash
```
Requirements: Docker 24+, 4 GB RAM, a domain (or an IP for LAN use). See `selfhost/`.

## Repositories

| Repo | What |
|---|---|
| [`kern`](https://github.com/KernALO/kern) | this repo — self-host distribution, docs, umbrella dev workspace |
| [`app`](https://github.com/KernALO/app) | SvelteKit PWA |
| [`core`](https://github.com/KernALO/core) | identity, workspaces, permissions, notifications + first-party modules (Fastify + kernel) |
| [`chat`](https://github.com/KernALO/chat) | chat + realtime WebSocket gateway |
| [`mail`](https://github.com/KernALO/mail) | outbound providers, IMAP/SMTP inbox, inbound intake |
| [`collab`](https://github.com/KernALO/collab) | Yjs/Hocuspocus collaborative editing |
| [`kernel`](https://github.com/KernALO/kernel) | `@kernalo/kernel`, `@kernalo/contracts`, `@kernalo/ui`, `@kernalo/sdk` |
| [`modules`](https://github.com/KernALO/modules) | first-party modules (`@kernalo/module-*`) |
| [`docs`](https://github.com/KernALO/docs) | documentation site |

## Develop (all repos, one workspace)

```bash
git clone https://github.com/KernALO/kern && cd kern
pnpm setup        # clones every repo into ./repos and installs deps (pnpm links @kernalo/* locally)
pnpm infra        # Postgres 18 · NATS · Valkey · MinIO · Mailpit   (docker compose -f dev/compose.yml)
pnpm db:migrate
pnpm dev          # turbo: app :5173 · core :4000 · chat :4100 · mail :4200 · collab :4300
```
Each repo also works standalone (`pnpm i && pnpm dev`) using published `@kernalo/*` packages.

## Docs
- `docs/PLAN.md` — product scope, architecture, roadmap
- `docs/ARCHITECTURE.md`, `docs/adr/`

## License
AGPL-3.0 — see `LICENSE`. Contributions are accepted under the `CLA.md`.
