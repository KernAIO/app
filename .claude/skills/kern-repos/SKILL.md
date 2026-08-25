---
name: kern-repos
description: The map of the KernAIO organisation — which repository holds what, where each is checked out, which port it owns, what it publishes and who depends on it; and how to regenerate that map when a repository is added, renamed, archived or given a port. Trigger before searching or changing anything across repositories, when asked where something lives, after `gh repo create` under KernAIO, and whenever the inventory might be stale.
---

# Where everything lives

Kern is one product in ten repositories. Nothing here is worth memorising, because the map
regenerates itself — this skill is how to read it and how to keep it true.

## 1. Read the map before you search

`references/inventory.md` is generated from the organisation and the local checkouts. It carries
every repository, its visibility, what it holds, where it is cloned on this machine, its port, and
the packages it publishes.

Read it **before** grepping across the workspace. A search that starts in the wrong repository is
how an afternoon disappears.

It costs a second to confirm the map is current:

```bash
node .claude/skills/kern-repos/scripts/sync.mjs
git -C <umbrella> status --short .claude/skills/kern-repos/references/inventory.md
```

Clean output means the map matches the org. A modified file means something changed — commit the
regenerated file with whatever you are working on.

## 2. The shape

| Kind | Repositories | Why it is its own repository |
|---|---|---|
| Umbrella | `kern` | The project's face: self-host distribution, ADRs, and the dev workspace that clones the rest |
| Services | `core`, `chat`, `mail`, `collab` | Each holds a workload that fails and scales differently — an HTTP API, open sockets, IMAP loops, CRDT merges |
| Front end | `app` | Every screen, hosting each module's client half |
| Libraries | `kernel`, `modules` | Published to npm as `@kernhq/*` and consumed by all of the above |
| Sites | `docs`, `website` | Starlight documentation, and the marketing site for kernaio.com |

Two things about that table are easy to get wrong:

- **`website` is deliberately outside `kern/repos/`.** The umbrella's `pnpm-workspace.yaml` globs
  `repos/*` and its lockfile is committed to a public repository; a private package under `repos/`
  would leak its dependency graph into that lockfile and break `pnpm setup` for contributors. It is
  cloned as a sibling of `kern/`, and installs on its own.
- **`ripgrep` from the umbrella does not reach it.** Searching "everywhere" means the umbrella *and*
  its siblings.

## 3. Where a change belongs

| The change | Repository | Skill to read first |
|---|---|---|
| A feature — issues, HR, CRM, automation | `modules` as `packages/<id>` | `kern-module` |
| A screen, a dialog, a view | `app` | `kern-ui` |
| A procedure, a migration, a permission key | the service that hosts the module | `kern-service` |
| A shared type, contract or event | `kernel/packages/contracts` | `kern-release` |
| Install, compose, Caddy, an ADR | `kern` | `kern-repo` |
| A documentation page | `docs` | `kern-writing` |
| Marketing copy, pricing, a landing page | `website` | — |
| A whole new service or package set | a new repository — but read the gate first | `kern-repo` |

**Contracts first.** A change to `@kernhq/contracts` lands and builds before its consumers. In CI a
repository builds standalone, where `workspace:*` does not resolve — consumers depend on the
published version, so the order is publish, then bump. `kern-release` covers it.

## 4. When the set of repositories changes

Run the sync, and commit its output **in the same commit** as the change that caused it. A map that
was only right on the day it was written is worse than no map, because it is believed.

Regenerate after any of these:

- a repository is created, renamed, archived or deleted
- a repository flips between public and private
- a service claims a port
- a package workspace starts or stops publishing a package
- someone clones a repository that was not on this machine before

```bash
node .claude/skills/kern-repos/scripts/sync.mjs
```

The script asks the organisation which repositories exist and the local checkouts what is inside
them. It reports what it cannot see rather than guessing, and it refuses to write anything if `gh`
is not signed in.

A **new service** needs more than the map — `kern-repo` §5 lists the rest: `scripts/dev-setup.sh`,
the port in the umbrella `CLAUDE.md`, `selfhost/docker-compose.yml`, `selfhost/Caddyfile` and
`selfhost/.env.example`. Skipping those is the classic failure: it works on the laptop and
self-hosters get a 502.

## 5. Ports

Services live in the 4000 band, one hundred apart; the front ends sit outside it on their
framework's own default. The inventory prints the current allocation and the next free number —
take it from there rather than counting by hand, because it already accounts for repositories that
are not in the pnpm workspace.

## 6. Verify

```bash
node .claude/skills/kern-repos/scripts/sync.mjs   # prints the repository count and the next free port
git -C <umbrella> diff .claude/skills/kern-repos/references/inventory.md
```

The diff is the proof. If you claimed a port, it appears in the Ports line and the next free number
has moved. If you added a repository, it has a row, and that row says where it is cloned — or says
plainly that it is not cloned here.

## 7. Every skill exists where a session can start

Three homes, one file each:

| A session started by | Reads skills from |
|---|---|
| Claude Code in `kern/` | `kern/.claude/skills/` |
| Claude Code in the workspace root | `.claude/skills/` — **symlinked** directories pointing at the copies above |
| Hermes (any profile) | `$HERMES_HOME/skills/` and `$HERMES_HOME/profiles/<profile>/skills/` |

The first pair are hardlinks inside shared directories and symlinked directories between them:
one inode with several names, so editing either path edits all, which is why nobody has had to
remember to copy anything. Creating a *new* file is the exception — a new skill written in one tree
stays invisible in the others until it is linked:

```bash
K=<workspace root>            # the directory that holds kern/
mkdir -p $K/.claude/skills/<skill>
ln $K/kern/.claude/skills/<skill>/SKILL.md $K/.claude/skills/<skill>/SKILL.md
for p in ~/.hermes/skills ~/.hermes/profiles/kern-dev/skills \
         ~/.hermes/profiles/kern-ops/skills ~/.hermes/profiles/kern-review/skills; do
  mkdir -p $p && ln -sfn $K/kern/.claude/skills/<skill> $p/<skill>
done
```

Check it with `stat -f %i` on both paths: the same inode number means one file, and no drift. Copy
instead of link and the two will disagree within a week.

The sync script finds the umbrella by walking up for the directory that holds `selfhost/`, so it
runs correctly from either path.
