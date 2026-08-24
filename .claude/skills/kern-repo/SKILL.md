---
name: kern-repo
description: Create a new repository in the KernAIO organisation and wire it into the workspace — the gate that decides whether a repo is warranted at all, the org furniture every public repo carries, CI with real service containers, ports, dev-setup, self-host compose and Caddy. Trigger when a new service or shared package set is proposed, when running `gh repo create` under KernAIO, or when an existing repo is missing its standard files.
---

# Adding a repository to KernAIO

Every repository is public and permanent. It costs a CI setup, a place in the dependency graph, a
release story, and a line in everyone's mental model — so the first job is to not create one.

## 1. The gate

A new repository is warranted only when the thing inside it is **independently deployable or
independently versioned**, and does not fit anywhere that already exists:

| You want | It goes in | Not a new repo |
|---|---|---|
| A feature (issues, HR, CRM, automation) | `modules` as `packages/<id>` | ✔ |
| Shared library, contract, SDK, design system | `kernel` as `packages/<name>` | ✔ |
| A long-lived-connection or loop process (WebSockets, CRDT, IMAP) | **new service repo** | |
| Documentation | `docs` | ✔ |
| Self-host distribution, scripts, ADRs | `kern` (umbrella) | ✔ |

`chat`, `collab` and `mail` are separate because a process that holds sockets open or polls mailboxes
scales and fails differently from an HTTP API. Nothing else has qualified yet. If your reason is
"it's a big feature", the answer is a module — see the `kern-module` skill.

Write the reason down. If it is a service, it is also an architectural decision: add an ADR in
`kern/docs/adr/` in the same change.

## 2. Create it

```bash
gh repo create KernAIO/<name> --public \
  --description "Kern <name> service — <one honest line>"
```

The org already holds `NPM_TOKEN` as an org secret available to **all** repositories, so a publishing
repo needs no secret of its own. Actions in this org **cannot open pull requests** — any release flow
must push to `main` directly (see `modules/.github/workflows/publish.yml`).

## 3. The furniture every public repo carries

Copy from the closest existing repo rather than inventing — `repos/chat` for a service,
`repos/modules` for a package workspace:

```
LICENSE (AGPL-3.0, or Apache-2.0 if it is framework — see LICENSING.md)
CLA.md  CODE_OF_CONDUCT.md  SECURITY.md  CONTRIBUTING.md
README.md  CLAUDE.md  .editorconfig  .gitignore  .npmrc  .nvmrc
biome.json  renovate.json  tsconfig.json  package.json
```

- `README.md` is written for a stranger, not for us: what this service is, how to run it alone, how it
  fits the whole. Use the `kern-writing` skill.
- `CLAUDE.md` carries the repo-specific half — its port, its env contract, its traps.
- `.npmrc` is `engine-strict=true`, `auto-install-peers=true`, `link-workspace-packages=true`.
- Package name `@kernhq/<name>`, `"license": "AGPL-3.0-only"`, `"type": "module"`, Node ≥ 24,
  `packageManager` pinned to the same pnpm as everywhere else.
- Scripts every repo answers to, because turbo runs them across all of them:
  `dev`, `build`, `start`, `lint`, `typecheck`, `test`.

## 4. CI that tells the truth

Copy `repos/chat/.github/workflows/ci.yml` and keep the service containers the suites actually need
(Postgres `pgvector/pgvector:pg18` everywhere, Valkey for presence, Mailpit for mail). Things learned
the hard way and worth re-reading before you edit a workflow:

- Address a service container as **127.0.0.1**, never `localhost` — the runner resolves `localhost`
  to `::1` first, where the published port is not listening, and `fetch` does not retry over IPv4.
- Do **not** set `registry-url` on `actions/setup-node` in an install job: it writes an `.npmrc` with
  a placeholder token, and npm answers a bad token with 404, so public packages appear to vanish.
- A repo builds **standalone** in CI. `workspace:*` resolves only inside the umbrella workspace —
  depend on published versions.
- Skipping a test because its infrastructure is missing is fine on a laptop and dishonest in CI. Fail
  when `process.env.CI` is set.

Then the second workflow, by repo kind:
- service → `docker.yml`, publishing `ghcr.io/kernaio/<name>` (copy it verbatim; the metadata tags,
  the `NODE_AUTH_TOKEN` build secret and the `KERN_VERSION` build arg are already right — that build
  arg is what makes the image report the release it was tagged as, so a copy that drops it produces a
  service claiming to be `0.0.0-dev` in production).
- package workspace → `publish.yml` plus `.changeset/`.
- docs → `pages.yml`.

A service also needs `Dockerfile` and `.dockerignore`.

## 5. Wire it into the workspace

A repo nobody clones does not exist. In the umbrella (`kern`):

1. `scripts/dev-setup.sh` — add the name to the `REPOS=(...)` array.
2. `pnpm-workspace.yaml` already globs `repos/*` and `repos/*/packages/*`; nothing to do unless the
   layout is unusual.
3. Claim a port and record it in `CLAUDE.md`. The current allocation and the next free number are
   in `kern-repos` → `references/inventory.md`; do not count by hand, it already accounts for the
   repositories that sit outside the pnpm workspace. Put it in the repo's `.env.example` too.
4. `selfhost/docker-compose.yml`: a service block using the `x-kern-env` anchor, `restart:
   unless-stopped`, and the image tag `${KERN_VERSION}`.
5. `selfhost/Caddyfile`: a route. Everything lives on one domain — `/api/<name>/*` to the service,
   `handle /api/*` to core last, because it is the catch-all.
6. `selfhost/.env.example`: any variable the compose block references, with a safe default and a
   comment saying what it is for.
7. The umbrella `README.md` and `docs/ARCHITECTURE.md` list the services. Add it there.
8. Regenerate the repository map, in this same commit:
   `node .claude/skills/kern-repos/scripts/sync.mjs`. It picks up the new repository, its port and
   anything it publishes. See the `kern-repos` skill.

Missing (4)–(6) is the classic failure: it works on the laptop and self-hosters get a 502.

## 6. Verify

```bash
cd /path/to/kern && bash scripts/dev-setup.sh   # clones it like a stranger would
pnpm infra && pnpm dev                          # it boots alongside everything else
curl -s localhost:<port>/api/health
gh run list -R KernAIO/<name> --limit 3         # CI actually passed, not "should pass"
```

Say which of these you ran. `gh run list` is the only proof that the workflow works; a workflow file
that looks correct has been wrong many times.
