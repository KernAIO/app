<!--
  GENERATED FILE — do not edit by hand.
  Regenerate with: node .claude/skills/kern-repos/scripts/sync.mjs
  Everything here is read from the KernAIO organisation and the local checkouts.
-->

# The KernAIO repositories

18 repositories, last synced 2026-08-25.

| Repository | Visibility | What it holds | Checked out at | Port |
|---|---|---|---|---|
| [`app`](https://github.com/KernAIO/app) | public | Every screen people actually use in Kern. | `kern/repos/app` | 5173 |
| [`brand`](https://github.com/KernAIO/brand) | public | The Kern logo, in every form anyone needs it — and the rules for using it. | `brand` | — |
| [`chat`](https://github.com/KernAIO/chat) | public | The Kern chat service — hosts @kernhq/module-chat | `kern/repos/chat` | 4100 |
| [`collab`](https://github.com/KernAIO/collab) | public | Documents that several people edit at the same time, in Kern. | `kern/repos/collab` | 4300 |
| [`core`](https://github.com/KernAIO/core) | public | Accounts, workspaces and permissions for Kern — who people are, and what they are allowed to do. | `kern/repos/core` | 4000 |
| [`docs`](https://github.com/KernAIO/docs) | public | Kern's documentation: how to install it, run it, and build modules for it. | `kern/repos/docs` | 4400 |
| [`kern`](https://github.com/KernAIO/kern) | public | One place for your team's work — issues, conversations, documents and people. Open source, self-hosted. Start here. | `kern` | — |
| [`kernel`](https://github.com/KernAIO/kernel) | public | The libraries every Kern service and module is built on. | `kern/repos/kernel` | — |
| [`mail`](https://github.com/KernAIO/mail) | public | The Kern mail service — hosts @kernhq/module-mail | `kern/repos/mail` | 4200 |
| [`module-billing`](https://github.com/KernAIO/module-billing) | public | Plans, subscriptions and entitlements for Kern — a first-party module, written the way yours would be | `kern/repos/module-billing` | — |
| [`module-chat`](https://github.com/KernAIO/module-chat) | public | Channels, threads and direct messages for Kern — a first-party module, written the way yours would be | `kern/repos/module-chat` | — |
| [`module-hr`](https://github.com/KernAIO/module-hr) | public | People, leave, attendance and approvals for Kern — a first-party module, written the way yours would be | `kern/repos/module-hr` | — |
| [`module-mail`](https://github.com/KernAIO/module-mail) | public | Workspace email delivery for Kern — a first-party module, written the way yours would be | `kern/repos/module-mail` | — |
| [`module-quire`](https://github.com/KernAIO/module-quire) | public | Spaces, pages and collaborative documents for Kern — a first-party module, written the way yours would be | `kern/repos/module-quire` | — |
| [`module-template`](https://github.com/KernAIO/module-template) | public | Apache-2.0 starting point for a Kern module — a whole working module: contract, server, schema, RLS, screens and strings | `kern/repos/module-template` | — |
| [`module-tracker`](https://github.com/KernAIO/module-tracker) | public | Projects, work items, cycles and workflows for Kern — a first-party module, written the way yours would be | `kern/repos/module-tracker` | — |
| [`modules`](https://github.com/KernAIO/modules) | public | Moved — every module now has its own repository. See the README. | _not cloned here_ | — |
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
- `@kernhq/workflow`

## Not cloned on this machine

- `modules` — `bash scripts/dev-setup.sh` clones the workspace repos; anything outside it is cloned by hand.
