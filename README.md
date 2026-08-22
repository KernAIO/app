<p align="center"><strong>Kern</strong> — the open-source all-in-one work platform.</p>
<p align="center">Issues & projects · Chat · Docs & Drive · HR & Recruiting · CRM · Automation · Mail · Calls · AI — one app, many workspaces.</p>

> Status: **pre-release (building in private)**. Target v1.0 — Q4 2026.

## Self-host (Docker)

```bash
curl -fsSL https://raw.githubusercontent.com/KernAIO/kern/main/selfhost/install.sh | bash
```
Requirements: Docker 24+, 4 GB RAM, a domain (or an IP for LAN use). See `selfhost/`.

## Repositories

| Repo | What |
|---|---|
| [`kern`](https://github.com/KernAIO/kern) | this repo — self-host distribution, docs, umbrella dev workspace |
| [`app`](https://github.com/KernAIO/app) | SvelteKit PWA |
| [`core`](https://github.com/KernAIO/core) | identity, workspaces, permissions, notifications + first-party modules (Fastify + kernel) |
| [`chat`](https://github.com/KernAIO/chat) | chat + realtime WebSocket gateway |
| [`mail`](https://github.com/KernAIO/mail) | outbound providers, IMAP/SMTP inbox, inbound intake |
| [`collab`](https://github.com/KernAIO/collab) | Yjs/Hocuspocus collaborative editing |
| [`kernel`](https://github.com/KernAIO/kernel) | `@kernaio/kernel`, `@kernaio/contracts`, `@kernaio/ui`, `@kernaio/sdk` |
| [`modules`](https://github.com/KernAIO/modules) | first-party modules (`@kernaio/module-*`) |
| [`docs`](https://github.com/KernAIO/docs) | documentation site |

## Develop (all repos, one workspace)

```bash
git clone https://github.com/KernAIO/kern && cd kern
pnpm setup        # clones every repo into ./repos and installs deps (pnpm links @kernaio/* locally)
pnpm infra        # Postgres 18 · NATS · Valkey · MinIO · Mailpit   (docker compose -f dev/compose.yml)
pnpm db:migrate
pnpm dev          # turbo: app :5173 · core :4000 · chat :4100 · mail :4200 · collab :4300
```
Each repo also works standalone (`pnpm i && pnpm dev`) using published `@kernaio/*` packages.

## Docs
- `docs/PLAN.md` — product scope, architecture, roadmap
- `docs/ARCHITECTURE.md`, `docs/adr/`

## License
AGPL-3.0 — see `LICENSE`. Contributions are accepted under the `CLA.md`.
