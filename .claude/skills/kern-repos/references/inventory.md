<!--
  GENERATED FILE — do not edit by hand.
  Regenerate with: node .claude/skills/kern-repos/scripts/sync.mjs
  Everything here is read from the KernAIO organisation and the local checkouts.
-->

# The KernAIO repositories

10 repositories, last synced 2026-08-22.

| Repository | Visibility | What it holds | Checked out at | Port |
|---|---|---|---|---|
| [`app`](https://github.com/KernAIO/app) | public | Every screen people actually use in Kern. | `kern/repos/app` | 5173 |
| [`chat`](https://github.com/KernAIO/chat) | public | Conversations in Kern, and the connection that keeps the whole application live. | `kern/repos/chat` | 4100 |
| [`collab`](https://github.com/KernAIO/collab) | public | Documents that several people edit at the same time, in Kern. | `kern/repos/collab` | 4300 |
| [`core`](https://github.com/KernAIO/core) | public | Accounts, workspaces and permissions for Kern — who people are, and what they are allowed to do. | `kern/repos/core` | 4000 |
| [`docs`](https://github.com/KernAIO/docs) | public | Kern's documentation: how to install it, run it, and build modules for it. | `kern/repos/docs` | 4400 |
| [`kern`](https://github.com/KernAIO/kern) | public | One place for your team's work — issues, conversations, documents and people. Open source, self-hosted. Start here. | `kern` | — |
| [`kernel`](https://github.com/KernAIO/kernel) | public | The libraries every Kern service and module is built on. | `kern/repos/kernel` | — |
| [`mail`](https://github.com/KernAIO/mail) | public | Email leaving Kern, and replies coming back. | `kern/repos/mail` | 4200 |
| [`modules`](https://github.com/KernAIO/modules) | public | The features Kern ships with — each one written the way yours would be. | `kern/repos/modules` | — |
| [`website`](https://github.com/KernAIO/website) | private | kernaio.com — the Kern marketing site (private) | `website` | 4500 |

## Ports

core 4000 · chat 4100 · mail 4200 · collab 4300 · docs 4400 · website 4500 · app 5173

Services sit in the 4000 band, one hundred apart. Next free: **4600** — claim it in the
repo's `.env.example` (`PORT=`) and in the umbrella `CLAUDE.md`, then re-run the sync.

## Published packages

**kernel** publishes:
- `@kernhq/contracts`
- `@kernhq/kernel`
- `@kernhq/sdk`
- `@kernhq/testing`
- `@kernhq/tsconfig`
- `@kernhq/ui`

**modules** publishes:
- `@kernhq/module-chat`
- `@kernhq/module-mail`
- `@kernhq/module-tracker`
- `@kernhq/workflow`
