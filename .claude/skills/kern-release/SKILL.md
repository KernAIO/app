---
name: kern-release
description: Get a change out of the workspace and into the registry and images — changesets, the contracts-first rollout order across repos, why a published package differs from the linked one, verifying against the real registry, and container tags for self-host. Trigger when publishing an @kernhq package, bumping a dependency between Kern repos, cutting a version, or when a consumer's CI fails on a package that "works locally".
---

# Releasing across the Kern repos

In the umbrella workspace every `@kernhq/*` package is a symlink to the source next door, so
everything resolves and nothing proves anything. CI, self-hosters and the app's Docker build resolve
the **published tarball**. The gap between those two is where the whole class of "works locally"
failures lives.

## Which repos publish what

| Repo | Publishes | Mechanism |
|---|---|---|
| `kernel` | `@kernhq/contracts`, `kernel`, `ui`, `sdk`, `testing`, `tsconfig` | changesets → npm |
| `modules` | `@kernhq/module-*` | changesets → npm |
| `app`, `core`, `chat`, `mail`, `collab` | `ghcr.io/kernaio/<name>` images | `docker.yml` on push/tag |
| `docs` | the docs site | `pages.yml` |

`NPM_TOKEN` is an org secret available to every repo. Nothing needs a per-repo secret.

## Rollout order — contracts first, always

1. `kernel` (contracts and libraries) — land, publish, verify on the registry.
2. `modules` — bump its `@kernhq/contracts` dependency to the published version, land, publish.
3. Services (`core`, `chat`, `mail`, `collab`) — bump module and kernel versions, land.
4. `app` last.

Merging a consumer first does not "just fail its own build" — it fails on the registry, in a repo you
then have to fix under pressure. Renovate automerges `^@kernhq/` bumps at any time, so consumers
often catch up on their own once the publish lands; check before hand-editing versions.

## Writing the changeset

Write it in the same commit as the change, in the publishing repo:

```bash
cd repos/modules && pnpm changeset      # pick packages, pick bump, one honest sentence
```

The summary appears in the changelog people read. "fix bug" helps nobody; "reject an issue transition
whose validator fails, instead of writing it and emitting the event" does.

Traps that have cost real time:

- **`"private": true` in a package.json** — `changeset publish` skips it silently. The workflow goes
  green and nothing is on the registry.
- **No changeset at all is still fine for a first release.** `changeset publish` compares each package
  against the registry, so a package that has never been released goes out anyway. Do not "fix" this
  by inventing a version bump by hand.
- **Publishing happens straight from `main`** (this org forbids Actions opening pull requests). The
  workflow rebases before versioning because runs queue rather than cancel; if you re-order that,
  concurrent pushes will try to publish a version that already exists.
- **The lockfile** is refreshed with `pnpm install --lockfile-only` after `changeset version`. Skipping
  it leaves every consumer's `--frozen-lockfile` install broken.

## Before you publish a module: pack it for real

A module ships `src/client` as source, and every relative import from it must be inside the tarball.
In the workspace every path resolves whether or not it is packed, so the failure only appears in the
app's build — once as `Could not resolve '../kql/ast.js'`.

```bash
cd repos/modules && pnpm check:pack
```

Extend the `files` array rather than the import when it complains.

## Verify against the registry, not the workflow

```bash
gh run list -R KernAIO/modules --limit 3          # did the publish job actually finish?
npm view @kernhq/module-tracker version           # is the version really there?
npm view @kernhq/module-tracker dist-tags
```

Only then bump consumers to that exact version. A `^0.1.4` in `core/package.json` for a `0.1.3` on the
registry produces an install error in CI and a confident-looking diff locally, because the workspace
link satisfies any range.

## Containers and self-host

Service images are tagged from branch, semver tag and `latest` on the default branch. Self-host pins
`${KERN_VERSION}`, so a release that people can install is a **git tag**:

```bash
git tag v0.2.0 && git push origin v0.2.0     # in each service repo that is part of the release
```

Then check `selfhost/docker-compose.yml`, `Caddyfile` and `.env.example` still describe reality — a
new env variable or port that never reached them is a 502 for every self-hoster and a green CI for us.

## Definition of released

- [ ] changeset written alongside the change
- [ ] `check:pack` clean (modules)
- [ ] publish workflow green — checked with `gh run list`, not assumed
- [ ] `npm view` shows the version
- [ ] consumers bumped to a version that exists, no `workspace:*` in published deps
- [ ] images tagged and self-host files updated if the surface changed
