---
name: kern-release
description: Get a change out of the workspace and into the registry and images — changesets, the contracts-first rollout order across repos, why a published package differs from the linked one, verifying against the real registry, and cutting a version of Kern itself: image tags, the signed release feed, schemaChanges and minPreviousVersion, and the bar a release has to meet now that instances apply it unattended. Trigger when publishing an @kernhq package, bumping a dependency between Kern repos, tagging a version, deciding whether something is ready to release, or when a consumer's CI fails on a package that "works locally".
---

# Releasing across the Kern repos

In the umbrella workspace every `@kernhq/*` package is a symlink to the source next door, so
everything resolves and nothing proves anything. CI, self-hosters and the app's Docker build resolve
the **published tarball**. The gap between those two is where the whole class of "works locally"
failures lives.

There are two different things called a release, and conflating them is the fastest way to break
somebody's instance:

- **publishing a package** — `@kernhq/*` to npm, continuously, for other repos to consume;
- **cutting a version of Kern** — a git tag that becomes `KERN_VERSION`, image tags, and an entry in
  the signed release feed. This is what reaches people.

Everything above "Containers and self-host" is the first. Everything below it is the second.

## Which repos publish what

| Repo | Publishes | Mechanism |
|---|---|---|
| `kernel` | `@kernhq/contracts`, `kernel`, `ui`, `sdk`, `testing`, `tsconfig` | changesets → npm |
| `modules` | `@kernhq/module-*` | changesets → npm |
| `app`, `core`, `chat`, `mail`, `collab` | `ghcr.io/kernaio/<name>` images | `docker.yml` on push/tag |
| `docs` | the docs site | `pages.yml` |

`NPM_TOKEN` is an org secret available to every repo. Nothing needs a per-repo secret.

## Before anything: know what is actually unpushed

```bash
pnpm status        # every checkout — dirty, unpushed, stashed, or never cloned
pnpm check:clean   # the same answer as an exit code, for a gate
```

Ten repositories means ten answers, and `website` sits *beside* the umbrella rather than under
`repos/`, so anything that loops over `repos/*` misses it without saying so. A release cut while one
repository still holds an uncommitted contract change is the "works locally" failure in its purest
form: the tag is real, the images are real, and the package the images install is the old one.

`pnpm status` also warns when a repository with a `.changeset/` directory has changes and no
changeset — the case where the commit lands, CI goes green, and the registry keeps the broken
version.

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

**Writing one is now optional, with one exception.** `publish.yml` infers a changeset from the
commit when none was written — `feat:` a minor, everything else a patch, naming the packages whose
directories the push touched. Write one by hand when the inferred summary would be a poor changelog
entry, or when several packages move by different amounts.

The exception is a **breaking change**. Whether an exported type changed shape is not visible in a
commit subject, and publishing one as a patch is what a consumer's caret range then installs
silently. A `!` subject or a `BREAKING CHANGE` trailer with no changeset fails CI *and* the publish,
deliberately.

```bash
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
- **A publishing repo's own `pnpm-lock.yaml` is committed, and installing at the umbrella never
  touches it.** Add a dependency while working in the workspace and the umbrella lock learns about
  it; the repo's does not, and its CI — which clones the repo alone and runs
  `--frozen-lockfile` — stops at `ERR_PNPM_OUTDATED_LOCKFILE` before a single test runs. Refresh it
  from inside the repo (`cd repos/kernel && pnpm install --lockfile-only`) in the same commit as the
  dependency. Only `kernel` and `modules` commit a lockfile today; the services do not.
- **A pre-1.0 minor bump leaves every consumer behind, silently.** `^0.1.0` does not accept `0.2.0`,
  so the moment `@kernhq/kernel` went to 0.2.0 every module resolved the *old* package on the
  registry and failed on a symbol that exists — while the workspace link kept the umbrella green.
  A `minor` changeset on a 0.x package is therefore a consumer bump too, in the same rollout.

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

## Cutting a version of Kern

Kern releases as one platform: every service image and every module inside it carries the same
`KERN_VERSION`, baked in at build time, and an upgrade moves all of them together. There is no
per-module release.

**Know what you are signing up for.** An instance set to `auto` takes a stable release *on its own*
once it has been out for its settling period (3 days by default). Nobody reads the tag first. A
release is therefore a claim that it is safe to apply unattended, at 03:00, to a database you cannot
see. If it is not, do not cut it — publish the packages and leave the tag.

### Before the tag

- **Every migration in the release is backward-compatible with the previous image.** See
  `kern-service` §5. If one is not, the release is `schemaChanges: breaking` and rolling it back
  costs a database restore.
- `selfhost/docker-compose.yml`, `Caddyfile` and `.env.example` describe reality — a new env
  variable or port that never reached them is a 502 for every self-hoster and a green CI for us.
- The compose file still parses. It once shipped not parsing at all:

  ```bash
  cd selfhost && docker compose --env-file .env.example config >/dev/null
  ```

### The tag, and the images

**You do not tag by hand any more.** `release.yml` in the umbrella does it — nightly at 02:00 UTC,
or on demand:

```bash
gh workflow run release.yml --repo KernAIO/app                    # bump read from the commits
gh workflow run release.yml --repo KernAIO/app --field bump=minor # override it
```

It refuses to release a `main` whose CI is red, works the version out of the commit subjects
(`feat:` is a minor, `!` or a `BREAKING CHANGE` trailer is a major, everything else a patch, and
below 1.0.0 a major is demoted to a minor rather than declaring stability nobody meant), tags that
one version across `core`, `app`, `chat`, `mail` and `collab`, waits for every image, and publishes
the umbrella release. Everything after that is automatic: `release-feed.yml` signs the feed and
dispatches `rollout.yml`, which pins `KERN_VERSION` in Coolify and waits for `/api/health` to report
it back.

Tagging one repository by hand produces an image nothing else knows about. If you need a version out
of band, dispatch the workflow.

`docker.yml` passes the tag in as the `KERN_VERSION` build arg, so the tag and the version the
container reports are the same string. A service that passes `version:` to `createKernel` overrides
that and makes `/api/health` lie — only tests may do it.

### The release feed

Publishing the GitHub release on the `kern` umbrella runs `release-feed.yml`, which reads the
**published images** (`docker run --rm <image> node dist/manifest.js`) and writes a signed
`releases.json` onto the release. Instances read it; the cloud rollout is triggered by it.

Two fields are judgement, not derivation, and both are load-bearing:

| Field | What it does | What a wrong value costs |
|---|---|---|
| `schemaChanges` | `none` / `additive` / `breaking` | `breaking` marked as `additive` means a rollback that silently corrupts, because nobody restored the database |
| `minPreviousVersion` | oldest version that may upgrade straight to this one | too low and an instance skips a migration a later one assumes; too high and everyone is forced through a pointless hop |

```bash
node scripts/release-feed.mjs --version 0.2.0 --schema additive --min-previous 0.1.0 --dry-run
```

Order matters: the images must exist before the feed job runs, because it reads them. A feed
generated against images that are still building fails loudly rather than lying — let it fail and
re-run the workflow.

**The feed cannot be signed without `KERN_FEED_PRIVATE_KEY`.** Generate the pair once with
`node scripts/release-feed.mjs --keygen`; the public half goes in core's `updates` service, the
private half in org secrets and nowhere else. Until both exist, every instance reports "no signing
key is configured" — which is correct, and is why it does not silently claim to be current.

## Definition of released

Publishing a package:

- [ ] changeset written alongside the change
- [ ] `check:pack` clean, and `check:versions` clean (modules)
- [ ] publish workflow green — checked with `gh run list`, not assumed
- [ ] `npm view` shows the version
- [ ] consumers bumped to a version that exists, no `workspace:*` in published deps

Cutting a version of Kern:

- [ ] every migration is readable by the previous image, or the release is marked `breaking`
- [ ] `docker compose config` passes on the self-host files, and they describe reality
- [ ] images tagged, and each reports the tag at `/api/health`
- [ ] `schemaChanges` and `minPreviousVersion` set deliberately, not defaulted
- [ ] feed job green and `releases.json` attached to the release
- [ ] you would be content for this to install itself, unattended, at 03:00
