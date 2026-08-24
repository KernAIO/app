---
name: kern-service
description: The completeness bar for Kern backend work — a module, a service, a contract or a migration. Covers implementing every procedure, authorisation on each one, tenant isolation, emitting events and realtime changes, idempotent migrations, honest errors, and verifying by running rather than by type-checking. Trigger whenever writing or reviewing anything under repos/core, chat, mail, collab, kernel or modules.
---

# Kern service completeness

Type-checking proves shapes line up. It proves nothing about whether the thing works, isolates
tenants, or tells the truth when it fails. Work through this before calling backend work done.

This is the bar for work built on the kernel as it stands. When the honest answer is that the kernel
has no seam for what the module needs — and the alternative is reaching into another module's tables
or patching a service from the outside — stop and read `kern-platform`: the extension point, the
template and every existing module move together, in one change.

## 1. Implement the whole contract

The contract is the promise. A procedure that exists in `contract` and not in `router` is a lie that
compiles.

```bash
# declared
grep -oE "^\s+[a-zA-Z]+: (base|oc)" src/contract/*.ts | sort -u
# implemented
grep -oE "^\s+[a-zA-Z]+: scoped\." src/server/router.ts | sort -u
```

Account for every one. Same for the module manifest: an `events` map whose events are never emitted,
or `objectTypes` with no resolver, is decoration.

A real example: the mail module shipped with providers, templates and a schema — and no
`defineServerModule` at all. Nothing was wired to anything.

## 2. Authorise every procedure

Each one carries `workspaceScoped(MODULE_ID)` (membership plus the module being enabled) **and** a
`requires('<permission>')` for the thing it does. Reads are not exempt: `issue.view` is a permission.

Procedures exposed on the module for other services (`procedures: {}`) are service-to-service. Guard
them with the equivalent of core's `requireService` — they must never be reachable by an end user.

## 3. Isolate tenants twice

- Every tenant table has `workspace_id`, a composite index starting with it, and an RLS policy from
  `rlsPolicySql`.
- Every query on those tables runs inside `kernel.database.withWorkspace(workspaceId, …)`, which sets
  the `app.workspace_id` the policy reads. Outside it the table appears empty — which looks like a
  bug and is actually the protection working.
- Never filter by an id that arrived in the request without checking membership first.
- Write a test that proves it: query as workspace A for a row belonging to B and assert nothing comes
  back.

## 4. Announce what changed

Every mutation does three things, not one:
1. writes the row,
2. `kernel.emit(...)` the typed event, so automations and other modules can react,
3. `kernel.realtime.change(workspaceId, { module, entity, id, op })`, so open clients update.

Skipping (3) is the usual cause of "I had to refresh to see it".

## 5. Migrations that survive a second run — and the image before them

- **A migration must leave the database readable by the previous image.** Add nullable columns and
  new tables; never drop, rename, narrow a type or add a `NOT NULL` without a default in the same
  release. Backfill in a job or a later release, not in the migration that adds the column.
  Destructive changes land one release later, after everyone has taken the release that stopped
  using the thing.

  This is not tidiness. Rolling an image back only works if the old code can read the new schema,
  and on cloud a rolling deploy runs both images against one schema deliberately. A release that
  cannot follow the rule is marked `schemaChanges: breaking` in the release feed, and rolling it
  back then costs a database restore. See `docs/adr/0002-platform-versioning-and-updates.md`.

- `CREATE SCHEMA IF NOT EXISTS` — the kernel creates the schema before migrating, so the bare form
  fails on boot. Note that `if not exists` is **not atomic** in Postgres: the kernel holds an
  advisory lock across schema creation and migration because four services booting together raced
  it into a unique violation on `pg_namespace`.
- Generated SQL never includes RLS. Add it in a hand-written migration alongside.
- Migrations are append-only once pushed. Fix forward.
- A deployment that is not a single Compose host migrates **once, before any new image serves**:
  `node dist/migrate.js` (and `--check` first, which reports what is pending and applies nothing).

## 6. Fail honestly

- Throw `KernError` with the right code (`NOT_FOUND`, `FORBIDDEN`, `CONFLICT`) — not a bare `Error`,
  which surfaces as an opaque 500.
- Never swallow an error to keep a happy path green. If a dependency is optional (chat not installed),
  handle its absence explicitly and say so in a comment.
- Log with `kernel.log` and never log secrets, tokens or full request bodies.

## 7. Jobs and subscriptions

Handlers are retried, so they must be idempotent — use a natural key or an idempotency row, never
"assume this runs once". A subscription that throws is redelivered; make sure that is safe.

## 8. Verify by running it

Boot the service and exercise the real path:

```bash
pnpm dev
curl -s localhost:<port>/api/health
# then the actual flow, with a real session cookie
```

Then `pnpm lint && pnpm typecheck && pnpm build && pnpm test`.

Bugs found this way today, none of which type-checking could have caught: every request body arrived
as `undefined` (the HTTP layer consumed the stream first); a second replica was rejected by NATS;
sign-up failed on a missing column; every search query errored on array binding; and no WebSocket
could authenticate at all.

State plainly what you exercised and what you did not.
