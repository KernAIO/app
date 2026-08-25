# CLAUDE.md — Kern project rules

Rules for anyone (human or AI agent) working on Kern repositories. These apply to every repo in the KernAIO org.

## We build in the open
The repositories are **public**, so every commit is visible the moment it is pushed:
- Never commit secrets, tokens, personal data, or machine-specific paths. Use `.env` (gitignored) + `.env.example`.
- Write READMEs, docs, and issue/PR text for external contributors, not for ourselves.
- Keep commit history clean and meaningful — it is part of what people judge the project by.
- Every repo carries LICENSE, CLA.md, CODE_OF_CONDUCT.md, SECURITY.md, CONTRIBUTING.md.
- **Two licences, split at the framework boundary.** The `kernel` repo and `modules`'
  `_template` + `workflow` are **Apache-2.0** so anyone can write a closed module; the product —
  `app`, `core`, `chat`, `mail`, `collab`, `docs`, this umbrella, the first-party modules — is
  **AGPL-3.0-only**. A new package inherits its repo's licence unless it is something a third-party
  module must import, and then it is Apache-2.0 with its own LICENSE file. Apache-2.0 packages take
  only permissive dependencies. If a module author has to import an AGPL package to get something
  done, move the API — never the licence. See `LICENSING.md` and
  `docs/adr/0005-licensing-and-the-module-boundary.md`.

## Git
- Author identity: `Navid Mirzaaghazadeh <mirzaaghazadeh@icloud.com>` (already set in each repo's local git config — plain `git commit` is correct; do not override with `-c`).
- **Do not add `Claude-Session:`, `Co-Authored-By: Claude`, "Generated with", or any AI trailer/branding to commit messages, PRs, or code comments.**
- Conventional Commits (`feat:`, `fix:`, `docs:`, `refactor:`, `test:`, `chore:`, with optional scope). Imperative mood, ≤ 72-char subject.
- Push to `origin main`. Never force-push. If `git pull --rebase` complains about unstaged files that aren't yours (parallel agents share worktrees), use `git -c rebase.autoStash=true pull --rebase`.
- **Never `git add -A` or `git add .`. Stage the paths you changed, by name.** Several agents share
  these checkouts, and another one is very often part-way through a new package in the same repo.
  `git add -A` sweeps their half-finished files into your commit and pushes them — under your commit
  message, without their lockfile entry, so CI fails at install for everyone. It happened on
  2026-08-24: a contact-address fix carried two unfinished modules into `main`. Run
  `git status --porcelain` first and stage from it; if you cannot name every path you are about to
  commit, you are not ready to commit. When it does happen, do not revert the other agent's files —
  they are still working on them; tell them instead, and repair what you broke.
- **Never ask permission to commit, branch, push, or pick a version bump** — those are yours, every
  time, and asking hands the work back. The only thing that is still the maintainer's call is cutting
  a release, and you ask that once, after the work is finished and green. See the `kern-ship` skill.

## Layout & workflow
- Umbrella dev workspace: `kern/` with sibling repos cloned under `kern/repos/<name>` (gitignored there). pnpm links all `@kernhq/*` packages via the umbrella workspace.
- Install dependencies ONLY via `kern/scripts/pnpm-install-locked.sh` (serialises pnpm at the umbrella root).
- Node 24 (`nvm use 24`), pnpm 10, TypeScript ~5.9, ESM/NodeNext, Biome for lint+format (run `pnpm exec biome check --write <paths>` before committing), Vitest.
- Contracts first: changes to `@kernhq/contracts` / module contracts land (and build) before their consumers.
- **One version for the platform.** Every image and every module in an instance carries the same
  `KERN_VERSION`, baked in at build time; npm versions are a packaging unit, not something a customer
  installs. A module's manifest version comes from `packageVersion(import.meta.url)`, never a literal
  — the literals drifted for months and every admin was shown the wrong version. See
  `docs/adr/0002-platform-versioning-and-updates.md`.
- **Every migration must leave the database readable by the image before it.** Add nullable columns
  and new tables; drop and rename one release later. This is what makes rolling an image back work
  without restoring a dump, and on cloud a rolling deploy runs both images against one schema on
  purpose. A release that cannot follow it is marked `schemaChanges: breaking` in the release feed.
- Modules own their data: Postgres schema `mod_<id>`, `workspace_id` + RLS on every tenant table, cross-module access only via `kernel.call()` and events. See `modules` repo `packages/_template`.
- **A module is the coarse switch; a capability is the one below it.** A module different customers
  want *different amounts* of declares capabilities — named sub-features with dependencies that a
  workspace switches, off for everyone rather than for one person. A disabled one answers **404, not
  403**: `forbidden` says the surface exists and you may not have it, which is false for a workspace
  that never enabled the feature, and it contradicts a shell that already hid the navigation.
  Switching one off must never destroy data — it is a flag in module settings, so anything needing a
  migration to reverse is not a capability. It is neither a permission (about a person) nor an
  entitlement (about a plan): a self-hosted instance has unlimited entitlements and still needs the
  switchboard. See `docs/adr/0007-module-capabilities.md`.
- **A widened shared contract is additive for *parsing* and breaking for *constructing*.** A new
  field with `.default([])` keeps every already-published manifest validating, which is the test
  everyone applies — but zod's inferred **output** type makes it required, so every service that
  builds one of those objects stops compiling. `capabilities` did exactly that to core, and CI
  could not see it because core's range said `^0.2.0` and a caret on 0.x does not cross a minor:
  CI resolved 0.2.x while every local build used 0.5.0. When you widen a contract, grep for the
  places that *construct* the type, and bump the consumer's range in the same change — green CI on
  a stale range is not evidence.
- **An entitlement key without an enforcement site is a lie.** `kernel.entitlements` declares what a
  plan may limit — seats, storage, modules, SSO, audit retention, API rate — and each key has exactly
  one place in core that checks it. Plan *values* are data an admin edits; the key set is not. Adding
  a key means adding its enforcement in the same commit, or the pricing page starts promising things
  again. When nothing answers `billing.entitlements.get`, every workspace is unlimited: that is what
  every self-hosted instance does on every request, so it is the default path and must not throw.
  See `docs/adr/0003-billing-entitlements-and-cloud.md`.
- Ports: app 5173 · core 4000 · chat 4100 · mail 4200 · collab 4300 · docs 4400. The live
  allocation, the next free number, and the map of every repository are generated —
  `node .claude/skills/kern-repos/scripts/sync.mjs`, then read the `kern-repos` skill.
- Dev DB on this machine: Homebrew Postgres 18 at `localhost:5432` (`kern`/`kern`); the compose Postgres listens on `${KERN_PG_PORT:-5432}` (5433 here).

## CI
Every service repository's CI runs the real suites, so the workflow starts the infrastructure they
need as service containers: Postgres (`pgvector/pgvector:pg18`) everywhere, Valkey for `chat`,
Mailpit for `mail`. Things learned the hard way:
- Address a service container as **127.0.0.1**, never `localhost` — a runner resolves `localhost` to
  `::1` first, where the published port is not listening, and `fetch` does not retry over IPv4.
- Do not set `registry-url` on `actions/setup-node` in an install job. It writes an `.npmrc` with a
  placeholder token, and npm answers a bad token with **404**, so public packages appear to vanish.
- A repository is built **standalone** in CI. `workspace:*` only resolves inside the umbrella
  workspace; depend on the published version instead.
- **Each repository's own `pnpm-lock.yaml` is what CI installs from, and you cannot refresh it from
  inside the umbrella.** Add a dependency to a package and the umbrella install updates the *umbrella*
  lockfile, leaving the repo's committed one stale — CI then fails every job at
  `ERR_PNPM_OUTDATED_LOCKFILE`, install-time, before a single test runs. Plain `pnpm install` in
  `repos/<name>` walks up and attaches to the umbrella; `--ignore-workspace` skips `packages/*` and
  cheerfully reports nothing to do. Clone the repo somewhere outside the workspace and run
  `pnpm install --lockfile-only` there, then copy the lockfile back.
- **Only `kernel` and `modules` commit a lockfile; `core`, `chat`, `mail`, `app` and `docs` do not.**
  Their CI is `if [ -f pnpm-lock.yaml ]; then --frozen-lockfile; else pnpm install; fi`, so a repo
  without one resolves fresh from its ranges every run and a repo with one fails at *install* the
  moment its lockfile drifts — before a single test. Check which kind you are in before adding a
  dependency; assuming from one repo's behaviour is how a publish job dies at
  ERR_PNPM_OUTDATED_LOCKFILE having built nothing.
- Skipping a test because its infrastructure is missing is fine on a laptop and dishonest in CI.
  Fail when `process.env.CI` is set.

## Writing
Documentation — READMEs, guides, runbooks, `docs/`, ADRs, and any procedure someone follows — uses
the `kern-writing` skill in `.claude/skills/`: decide where it belongs first, goal before steps, one
action per step, conditions before commands, an observable result after every important action, and
never the present tense for something that is not built. It governs documents for readers. Code
comments and commit messages keep the voice they have; user-facing strings belong to `kern-language`.

## Quality bar
- `pnpm typecheck && pnpm lint && pnpm test && pnpm build` must pass before pushing.
- UI follows `app/DESIGN.md` (Ink/paper design system) and must work in RTL (fa/ar) and dark mode.
- All user-facing strings go through i18n (Paraglide) — no hardcoded English in components.
- **A screen that works is not finished; it has to be pleasant.** Kern is judged as a product, so
  the things that read as amateur are defects here, not polish: text nobody can read in dark mode,
  a blank browser tab, an icon button a screen reader calls "button", a control too small to hit, a
  page that scrolls sideways in Persian. None of that fails a build or a type-check, so it is
  guarded by a machine instead: `repos/app/tests/e2e/ux.spec.ts` sweeps **every route in four
  renderings** — light and dark, LTR and RTL — against the rules in `ux-audit.ts`, and CI runs it.
  It is the only check that looks at the *rendered* interface. Adding a route means adding it there.
  What a machine cannot judge — whether the copy is kind, whether the layout has rhythm — is the
  `kern-ui` skill's job, and it is still yours to check.
- **Two of these defects are invisible from the source, so measure rather than eyeball.** A colour
  pair's contrast is arithmetic, not taste: compute it against the surface the text actually sits on
  and against the *palest* one it could sit on. And `opacity` on a row fades its text against the
  page — a "muted" row at 0.5 is unreadable, whatever its colour token says. Mute with a colour.

## Keeping this file current
This file is how the next person — or the next agent — avoids repeating what we already worked out.
When you learn something durable, add it here **in the same commit as the change that taught you**:
- a trap that cost you time (a silent failure, a misleading error, a tool that lies about success)
- a convention you had to infer from reading several files
- a decision and the reason behind it, especially where the obvious choice is wrong
Keep it specific and short. Delete anything that stops being true — a stale note is worse than none.

---

# This repository: kern (umbrella)

The project's face and the local development workspace. It holds the self-host distribution
(`selfhost/`), the docs and ADRs (`docs/`), and the scripts that clone every other repository into
`repos/` and link them with pnpm.

```bash
pnpm setup     # clone every repo into ./repos and install
pnpm infra     # Postgres 18, NATS, Valkey, MinIO, Mailpit
pnpm dev       # every service with hot reload
```

**Things worth knowing**
- `repos/` is gitignored: each subdirectory is its own git repository with its own remote.
- **The umbrella has no turbo task graph, and cannot have one.** Every repo carries its own
  `turbo.json`, and CI clones that repo alone — so the file has to be a *root* config, while a
  package inside this workspace would need `extends: ["//"]`, which turbo rejects at a root.
  `pnpm dev|build|lint|typecheck|test` therefore run `scripts/run-all.sh`, which calls each
  repo's own script in dependency order (kernel → modules → services → app → docs). It reports
  every failure rather than stopping at the first, and `--parallel` is what `pnpm dev` uses.
- **`pnpm status` is the only honest answer to "is everything committed?"** Ten repositories means ten
  answers, and `website` is checked out *beside* the umbrella rather than inside `repos/`, so a loop
  over `repos/*` misses it — silently, which is the worst way to miss something. The script finds
  every checkout, lists every path (never a truncated `head`), and reports unpushed commits, stashes,
  a detached HEAD and any repository the organisation has that is not cloned here. It **exits 1** when
  anything is unpushed, so it can gate rather than only inform: `pnpm check:clean` is the same check
  without the detail. Run it before you tag anything.
- Dependencies are installed at this root, which is why every repo uses
  `scripts/pnpm-install-locked.sh` — several agents or terminals installing at once will corrupt the
  store otherwise.
- The dev Postgres container listens on `${KERN_PG_PORT:-5432}`. On a machine that already runs
  Postgres on 5432 (Homebrew, for instance), set `KERN_PG_PORT=5433` so the container stops shadowing
  it — and point `DATABASE_URL` at whichever one you actually mean.
- `selfhost/` is what users run. Changing a service's port, image name or env contract means changing
  `docker-compose.yml`, `Caddyfile`, `.env.example` and `coolify/docker-compose.yml` here too — and
  `install.sh`'s file list, which is what an existing instance never re-downloads.
  `scripts/check-selfhost-drift.py` is what notices when the Coolify copy is left behind; CI runs it.
- **The images are `amd64` only.** `docker.yml` in each service repo has no `platforms:`, so
  `build-push-action` builds for the runner. Every requirement we publish says x86-64 because of
  that one omission — adding `platforms: linux/amd64,linux/arm64` (and QEMU) is what changes it.
- **The memory figures in the docs and on the website are measured, not estimated.** Idle RSS of the
  real containers, plus `node dist/main.js` for `core` run against them. Re-measure before changing
  the numbers rather than adjusting them by feel; `core` is the largest Kern service, so it is the
  one worth measuring.
- **Do not override a Kern service's healthcheck in Compose.** Every service image already carries
  one, and it is the only shape that works: the images are `node:24-slim`, which has neither `wget`
  nor `curl`, and the services listen on IPv4 only, so `localhost` resolves to `::1` and is refused.
  All three compose files carried `test: ["CMD","wget","-qO-","http://localhost:4000/api/health"]`
  for `core`, which failed on both counts — so `core` was permanently unhealthy, and `core-worker`,
  `chat`, `mail` and `collab` all wait on `condition: service_healthy` and therefore never started.
  A stack that looks like it booted with four services missing is this. The image probes
  `127.0.0.1` with `node -e "fetch(...)"`; let it.
- **There are now three copies of the stack, and `cloud/` is the third.** `selfhost/` is the bare
  host, `selfhost/coolify/` is what a customer pastes into their own Coolify, and `cloud/` is the
  instance we run at app.kernaio.com. It differs in exactly one thing: `S3_PUBLIC_ENDPOINT` points
  at its own hostname, because Cloudflare's Free and Pro plans reject a request body over 100 MB
  while `UPLOAD_MAX_PUT_BYTES` signs single-PUT URLs up to 500 MB — proxy the storage path and every
  large upload dies as a 413 the browser reports as a network error. So MinIO gets `files.` on a
  DNS-only record and the app keeps the CDN. `scripts/check-selfhost-drift.py` checks all three:
  a copy may differ in a variable's *value*, never in the set of keys or the Caddy routes.
- **`selfhost/coolify/` mounts nothing.** A Compose file pasted into Coolify has no files beside it,
  so the Caddy config is a heredoc inside the container's command and the Postgres init script is
  gone (core's first migration creates the extensions anyway). Keep the heredoc free of `$` —
  Compose interpolates the command string before the shell ever sees it.
- **A `HEALTHCHECK` with no `--start-period` fails a Coolify deploy, on a container that works.**
  Coolify gates a release on Docker's health status and polls it about ten times. Docker's default
  interval is 30s and the first probe fires almost immediately — before the server has bound — so
  every poll re-reads that same stale failure (identical `Start` timestamp in the log is the tell)
  and the release is rolled back. Give every image `--interval=10s --start-period=15s`.
  And probe **127.0.0.1, not localhost**: `nginx.conf` replacing nginx's `default.conf` means
  `10-listen-on-ipv6-by-default.sh` never patches it, so nginx is IPv4-only while busybox wget
  tries `::1` first and is refused. Same trap as the CI note above, one layer down.
- **Caddy behind another proxy rewrites `X-Forwarded-Proto` to `http` and replaces the client IP**
  unless the proxy in front is trusted. On Coolify that turns every request into one the services
  believe arrived unencrypted. `servers { trusted_proxies static private_ranges }` in the global
  block is what preserves them; the host install does not need it, because there it is the edge.
- **Run `docker compose config` after editing `docker-compose.yml`.** A bare `${VAR}` inside a YAML
  *flow* mapping (`environment: { A: ${A} }`) opens a nested mapping and the whole document stops
  parsing — the file shipped that way and `docker compose config` failed on it, which no test
  covered because nothing parsed it. Quote every interpolation inside `{ }`.
- **A standalone repo needs its own `pnpm.overrides` too, for the same reason the umbrella has one.**
  A published module whose range still says `@kernhq/kernel: ^0.2.0` drags a second kernel into a
  consumer's tree, and a caret on 0.x never crosses a minor — so `core` installed kernel 0.2.0 for
  `billing` and 0.6.0 for itself and `tracker`. Two structurally distinct declarations of
  `ServerModule`, so `[trackerModule, billingModule]` stopped being assignable to `ServerModule[]`
  even though both packages export exactly the same type. Invisible locally, because the umbrella
  already pins these. `"overrides": { "@kernhq/kernel": "$@kernhq/kernel" }` forces one copy, which
  is the honest model: there is only ever one kernel at runtime. Reproduce this class of bug with a
  registry install in a clone outside the workspace — a local build resolves differently and proves
  nothing.
- **`pnpm.overrides` pins `@kernhq/contracts|kernel|sdk|ui` to `workspace:*`.** Without it a repo
  whose dependency range excludes the local version (app wanted `module-tracker@^0.3.0`, the
  workspace had 0.2.1) installs the published module, which drags a published `@kernhq/contracts`
  into the tree. Two copies of the contracts then coexist, and `svelte-check` resolves the stale one
  while plain `tsc` resolves the linked one — so the app reports errors for procedures that exist,
  in files nobody touched. Plain `tsc` passing is not evidence here; `pnpm typecheck` is.
- Release feed: `node scripts/release-feed.mjs --keygen` makes the ed25519 pair. The public half goes
  in core's `updates` service, the private half in the `KERN_FEED_PRIVATE_KEY` org secret. Until both
  exist, instances report "no signing key is configured" rather than claiming to be current.
- **A workspace package can silently resolve to a registry copy, and then local edits do nothing.**
  `link-workspace-packages=true` links a package the first time the workspace version satisfies the
  range; pnpm does not re-evaluate a resolution that still satisfies, so once the lockfile records
  a registry version it keeps it. Today `@kernhq/module-mail` is linked while chat and tracker are
  registry copies, in the same install. Check with
  `readlink repos/app/node_modules/@kernhq/module-<id>` before wondering why an edit to a module's
  client had no effect — the answer is that the app never read your file. This lockfile is
  gitignored, so the linking state is per machine: two people on the same commit can disagree about
  which packages are linked, and only one of them sees the bug.
- **Editing a module's client means a publish round trip, and it is worth checking that first.**
  `./client` ships as source, so an edit is visible immediately *if* the package is linked and not
  at all if it is not. Either way the consumer's CI installs from the registry, so the change has to
  publish before the consumer's commit can go green: module changeset and push, wait for the version
  to appear on npm, then bump the app.
- **`tsx watch` processes pile up, and the oldest one owns the port.** Seven `core` watchers were
  running at once from earlier sessions; the first to bind :4000 keeps it, and every later one
  reloads your edits into a process nobody can reach. The symptom is a service that ignores a change
  it has definitely seen — `curl localhost:4000/api/core/openapi.json` shows the old surface while
  the log shows a reload. Check with `ps -eo pid,command | grep "tsx/dist/cli.mjs watch"` before
  concluding a change did not take, and expect one pid per service.
