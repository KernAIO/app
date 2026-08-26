# ADR 0002 — One version for the platform, and how an instance learns about a new one

- Status: accepted (2026-08-22)
- Context: modules carried two versions that had already drifted (`@kernhq/module-chat` shipped as
  0.2.0 and reported `'0.1.0'`, the literal typed into `defineModule`), `workspace_modules.installed_version`
  recorded that literal and nothing read it, nothing told an admin a release existed, and boot-time
  migrations had no lock even though Compose starts `core` and `core-worker` together. The question
  behind all of it: does Kern offer updates per module, or as a platform?

## Decision

**1. The platform is the unit. `KERN_VERSION` is the only version an instance has.**

Every service image and every module in it carries the same version, baked into the image at build
time, and an upgrade moves all of them together. Per-module install is rejected for v1.0:

- module clients are compiled into the app bundle, so a module's interface cannot be replaced
  without rebuilding the app;
- `kernel.call()` and the event contracts are checked at compile time against `@kernhq/contracts`, so
  a module ahead of its host does not type-check rather than degrading;
- everything shares one Postgres, so two module versions means two migration histories against one
  database;
- the test matrix for N independently versioned modules against M platform versions is not something
  this project can honestly claim to have tested.

npm versions stay the developer-facing packaging unit (changesets, contracts-first rollout).

**2. A module reports the version of its own package.** `packageVersion(import.meta.url)` reads it at
runtime; a string literal is never bumped by a release and is what the admin console shows. A check
in the modules repo's CI fails the build when the two disagree.

**3. Modules may declare `minKernel`, and the kernel refuses to boot when it is not satisfied** —
before any migration runs. First-party modules rarely need it; it exists for custom builds, where a
module package and the images around it can move separately, and where the failure would otherwise
appear much later and look like something else.

**4. The panel owns the decision; the host owns the act.**

An instance has one update policy — `off`, `notify` or `auto` — set by an instance admin in the
interface, with a window, a time zone and a settling period. There is no per-module policy, for the
same reason there is no per-module version.

`auto` is real: the instance applies stable releases itself, through the same preflight, snapshot,
maintenance mode and verification as a manual upgrade. What it will not do is decide on its own —
the thing on the host asks `updates-cli plan` and obeys the answer, so what the panel promises and
what happens at 03:00 are one computation rather than two that can drift.

Two ways to provide that host-side runner, both opt-in in their own way:

- **A systemd timer**, offered by `install.sh`, checking hourly. No new privilege: the host already
  runs Docker. This is the default and the recommended one.
- **An updater container** behind the `autoupdate` compose profile, for hosts without systemd. It
  mounts the Docker socket, which is root-equivalent, so it ships off with the danger stated plainly.
  Its image tag is deliberately not `${KERN_VERSION}`, so an upgrade does not recreate the container
  running the upgrade.

A failed automatic upgrade is not retried. It notifies the admins and holds until a person sets the
mode to `auto` again — retrying the release that just broke turns one bad night into a week of them,
and the hold needs an exit that is not "wait for the next release".

**4b. Update awareness is offered; applying stays on the host.** Core reads a signed `releases.json`
on a schedule and shows an instance admin the running version, the newest stable release, the
per-module version diff, anything blocking the upgrade, and the exact command. Kern never upgrades
itself and mounts no Docker socket — a container able to replace its own host is a larger promotion
than the feature is worth.

The check is a plain GET for a static file, sends nothing about the instance, and can be switched
off. The document is `{payload, signature}` with the signature over the exact bytes served, verified
before parsing: re-encoding JSON is not guaranteed to reproduce the same bytes.

**5. Migrations follow expand/contract.** Every migration must leave the database readable by the
image before it. Destructive changes land one release later. This is what makes "roll the image back
and the old one still runs" true rather than hoped for, and on cloud it is the correctness condition
rather than a nicety, because a rolling deploy runs both images against one schema on purpose. A
release that cannot follow it is marked `schemaChanges: breaking`, and rolling it back restores the
database too.

**6. An upgrade is recoverable, not risk-free.** `kern-upgrade.sh` runs a preflight (compose valid,
database reachable, disk for a snapshot, migration dry run, `minPreviousVersion`, required env),
takes a `pg_dump` plus `.env` and compose files into a retained snapshot, closes the API with
maintenance mode, migrates once, brings `core` up and waits for ready, then verifies every service
reports the new version. Any failure prints the rollback command. Literal zero risk is not on offer
and is not claimed.

**7. Cloud is managed by us and tracks latest stable automatically.** `release-feed.yml` dispatches
`rollout.yml` (in this repository) once a release's feed is signed: pin `KERN_VERSION` in Coolify,
deploy, wait for `app.kernaio.com` to report it, then keep watching it for a few minutes rather than
trusting one successful poll. A rollout that never lands, or lands and then falls over, is redeployed
back to whatever was live before automatically — see ADR 0009's addendum below.

This is not the surge-and-canary rollout described in earlier drafts of this decision: one Coolify
application serves every cloud workspace, so a new version is live for everyone the moment it reports
healthy, and nothing in this stack exports a request error rate to gate on. What exists today is a
health/reachability regression check with an automatic rollback, not a traffic-split canary — this
line said otherwise before it was checked against what actually runs, and against `rollout.yml` at
that time, which had no rollback at all. Weighted-traffic canary would need infrastructure
(a second application instance and a load balancer that can split by weight) this stack does not have
yet.

## Consequences

- `installed_version` becomes meaningful only once something writes it from the migration path; it
  is still written from the enable path today, which is a follow-up rather than part of this ADR.
- The feed cannot work until an ed25519 pair is generated (`node scripts/release-feed.mjs --keygen`),
  the public half is pasted into core's updates service and the private half is stored as the
  `KERN_FEED_PRIVATE_KEY` organisation secret. Until then an instance reports "no signing key is
  configured" rather than silently claiming to be current.
- `create ... if not exists` is not atomic in Postgres; schema creation moved inside the migration
  advisory lock and catalogue duplicate errors are treated as success.
- The marketplace for community modules (v1.x) is the thing that would reopen decision 1. It needs
  runtime loading, which needs a boundary that does not exist yet.
