<p align="center"><img src="assets/kern-mark.svg" width="64" alt=""></p>

<h1 align="center">Kern</h1>

<p align="center">One place for your team's work — issues, conversations, documents and people.<br>
Open source. Self-hosted. Yours.</p>

---

Most teams pay for four tools that do not talk to each other. An issue tracker. A chat app. A wiki.
Something for HR. Every link between them is a copy-paste.

Kern is one application instead. An issue can have its own channel. A message can become an issue.
The people in your HR records are the people in your projects. Nothing is synchronised, because
nothing is separate.

You run it on your own machine. Your data stays there.

## What works today

Kern is **pre-1.0 and in active development**. This list is what actually runs, not what is planned.

| Area | State |
|---|---|
| Accounts, workspaces, roles and permissions | Working |
| Issues and projects — list, board, detail, queries, cycles, time tracking | Working |
| Chat — channels, direct messages, threads, reactions, presence | Working |
| Notifications across every workspace you belong to | Working |
| Files, search, audit log, workspace settings | Working |
| Email the platform sends (per-workspace providers) | Working |
| Documents several people edit at once | Service runs; no editor yet |
| Personal mail inbox (your own IMAP account) | Not built |
| Docs, drive, calendar, HR, recruiting, CRM, automation, calls, AI | Not built |

Everything above is one workspace or many, in English, German, Persian or Arabic, left-to-right or
right-to-left, in light or dark.

## Install Kern

Goal: run Kern on your own server and open it in a browser.

You need:

- A machine with Docker 24 or newer.
- 4 GB of RAM.
- A domain name, or an IP address for a machine on your network.

> **Not yet.** The container images are still private, so this installer cannot pull them. Until the
> first release, use **[Develop Kern](#develop-kern)** below, which runs everything from source.

### 1. Run the installer

```bash
curl -fsSL https://raw.githubusercontent.com/KernAIO/kern/main/selfhost/install.sh | bash
```

The installer asks for your domain, an admin email address and an admin password. It writes them to
`~/kern/.env` along with freshly generated secrets.

**Expected result:** the installer prints the address of your new Kern.

### 2. Sign in

1. Open the address the installer printed.
2. Sign in with the admin email address and password you chose.

**Expected result:** Kern opens on your first workspace.

### If the installer cannot reach Docker

**Problem:** the installer stops with `Docker is required`.

**Cause:** Docker is not installed, or your user cannot talk to the Docker daemon.

**Solution:**

1. Install Docker from https://docs.docker.com/get-docker/.
2. Run `docker ps` to confirm it answers.
3. Run the installer again.

## Develop Kern

Goal: run every Kern service on your own machine, with hot reload.

You need:

- Node 24 and pnpm 10.
- Docker, for Postgres and the other infrastructure.
- Roughly 5 GB of disk space.

### 1. Clone and install

```bash
git clone https://github.com/KernAIO/kern
cd kern
pnpm setup
```

`pnpm setup` clones every Kern repository into `repos/` and installs all dependencies at once.

**Expected result:** `repos/` contains `app`, `core`, `chat`, `mail`, `collab`, `kernel`, `modules`
and `docs`.

### 2. Start the infrastructure

```bash
pnpm infra
```

This starts Postgres, NATS, Valkey, MinIO and Mailpit in Docker.

**Expected result:** `docker ps` lists five containers with names beginning `kern-dev`.

### 3. Start everything

```bash
pnpm dev
```

Each service creates its own database tables the first time it starts, so there is nothing to
migrate by hand.

**Expected result:** the app is at http://localhost:5173, and the services are at :4000 (core),
:4100 (chat), :4200 (mail) and :4300 (collab).

### Work on the interface without any of that

```bash
cd repos/app
pnpm dev:mock
```

This runs the whole interface against demo data held in memory. It needs no database and no
services, and it is what the end-to-end tests run against.

### If Postgres will not start

**Problem:** `pnpm infra` fails, or a service cannot connect to the database.

**Cause:** something else is already listening on port 5432 — often a Postgres you installed
yourself.

**Solution:**

1. Set `KERN_PG_PORT=5433` in `.env`.
2. Point `DATABASE_URL` at whichever Postgres you mean to use.
3. Run `pnpm infra` again.

## How Kern is put together

Every feature is a **module**. A module owns its own database schema, its own API and its own
screens, and it declares what it contributes. A workspace can switch any module off, and every trace
of it disappears — no navigation, no routes, no notifications.

The modules Kern ships with are written against the same public interfaces anyone else would use. If
you can build a module, you can build a feature that sits beside ours as an equal.

| Repository | What it is |
|---|---|
| [`kern`](https://github.com/KernAIO/kern) | This one: how to install Kern, the documentation, and the workspace that links the rest |
| [`app`](https://github.com/KernAIO/app) | Every screen people use |
| [`core`](https://github.com/KernAIO/core) | Accounts, workspaces, roles, permissions, notifications, files and search |
| [`chat`](https://github.com/KernAIO/chat) | Conversations, and the connection that keeps everything live |
| [`mail`](https://github.com/KernAIO/mail) | Email leaving Kern, and replies coming back |
| [`collab`](https://github.com/KernAIO/collab) | Documents several people edit at the same time |
| [`kernel`](https://github.com/KernAIO/kernel) | The libraries every service and module is built on |
| [`modules`](https://github.com/KernAIO/modules) | The features Kern ships with |
| [`docs`](https://github.com/KernAIO/docs) | The documentation site |

Read `docs/ARCHITECTURE.md` for how the pieces fit, and `docs/PLAN.md` for where this is going.

## Contribute

Start with [CONTRIBUTING.md](CONTRIBUTING.md). It covers the repository layout, the tools, and what a
change has to pass before it lands.

Kern is built in the open. Every commit is public the moment it is pushed. That is why the rules
in [CLAUDE.md](CLAUDE.md) apply to everyone — people and coding agents alike.

## Licence

[AGPL-3.0](LICENSE). You may run, read, change and share Kern.

If you offer a changed Kern to other people over a network, you have to share your changes under the
same licence. Contributions are accepted under the [CLA](CLA.md).
