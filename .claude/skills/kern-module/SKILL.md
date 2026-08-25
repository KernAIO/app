---
name: kern-module
description: How a Kern feature comes into existence — decide whether it belongs to an existing module, a new module, or a new service, then wire it end to end: package, contract, schema and RLS migration, server module, client module, registration in a host service and the app shell, changeset and release. Trigger when starting a feature area, creating `repos/modules/packages/<id>`, or asking "where should this live".
---

# Growing Kern with a module

A module is the unit of growth. It owns its tables, its permissions, its events and its screens, and
a workspace can switch it off and have every trace of it disappear. Getting a new one wired takes
about nine steps, and skipping any one of them produces something that compiles and is not reachable.

These steps describe the module system **as it is today**. If the feature needs something the module
contract does not offer, that is not a reason to bend the feature into the template's shape: read
`kern-platform` and move the kernel, `_template` and the existing modules together. The template is
the current best answer, not the law.

## 1. Decide where it lives — before writing anything

Three answers, in order of how often they are right:

**Extend an existing module** when the feature is about nouns that module already owns. A "release"
belongs to `tracker` because it is made of issues. Adding a package for it would mean two modules
writing to each other's tables, which the architecture forbids.

**A new module** when it brings its own nouns, its own permission keys and its own tables — and a
workspace could plausibly turn it off. `hr`, `crm`, `recruit`, `automation` are all this. It does not
need its own process: a module is hosted by whichever service imports it.

**A new service** only when it has a *runtime* reason to be a separate process — long-lived
connections (`chat`), a CRDT server (`collab`), IMAP polling loops (`mail`). "It feels big" is not a
runtime reason. If you conclude a service is needed, read the `kern-repo` skill; the module still
gets built exactly as below, it is just imported somewhere else.

Say which of the three you picked and why, in one sentence, before you start.

## 2. Create the package

```bash
cd repos/modules
pnpm new-module <id>          # scripts/new-module.mjs
```

**`@kernhq/module-template` is published, and that is the whole point of it.** It was `private: true`
until 2026-08-25, which meant the Apache-2.0 half of the licensing split could only be got by cloning
an AGPL-3.0 repository — the promise in ADR 0005 was real in the licence header and unreachable in
practice. Somebody outside this organisation starts from the published package; `pnpm new-module`
is the shortcut for people who already have the workspace. Both must produce the same module, so a
change to one is a change to both.

It copies `_template` and rewrites every `template` identifier — including the URLs the manifest
declares and the namespaced keys in the message bundle. There is no app half: a module is one
package, and `_template` is a whole one. It prints what is left. Do not hand-copy `_template`: the
generator exists because every one of the fixes below was once forgotten.

Read the result against these anyway, and if the generator has fallen behind the template, fix the
generator in the same change (`kern-platform` §5) — each of these has bitten:

- `name`: `@kernhq/module-<id>`, and **delete `"private": true`**. A private package is silently
  skipped by `changeset publish`, so the release "succeeds" and nothing reaches the registry.
- Add `"publishConfig": { "access": "public" }` and `"repository": { …, "directory": "packages/<id>" }`.
- `files`: `dist`, `migrations`, **and every `src/` directory the client entry reaches**. The client
  ships as source — consumers compile the Svelte themselves — so anything it imports must be in the
  tarball. `./client` exports point at `./src/client/index.ts`, not at `dist`. See `packages/tracker`.
- `MODULE_ID` in `src/contract.ts`, the schema name `mod_<id>`, and `schemaFilter` in
  `drizzle.config.ts` must all agree.
- The manifest's `version` is `packageVersion(import.meta.url)`, never a string literal. Nothing
  bumps a literal when changesets releases the package: chat shipped as 0.2.0 and told every admin
  it was 0.1.0, and that literal is what `workspace_modules.installed_version` recorded.
  `pnpm build && pnpm check:versions` fails the build if the two ever disagree again.
- Set `minKernel` only if the module genuinely needs a platform newer than the one it ships with.
  Modules are released together with everything else, so it is for custom builds — and the kernel
  refuses to boot rather than failing later at some unrelated call site.

## 3. Contract first

`src/contract.ts` (or `src/contract/`) is the promise the rest of the system compiles against:
procedures, `defineEvent` names, `definePermissions` keys. It lands and builds before any consumer —
core, the app, another module — imports it. Contracts first is not a style preference: consumers
resolve the *published* package in their own CI, so a consumer merged first cannot build.

Permission keys are `<id>.<noun>.<verb>` and reads need one too.

**Capabilities, if this module is one different customers want *different amounts* of.** Most are
not: chat, mail, the tracker and billing are each coherent only as a whole, and a capability nobody
switches is a switch nobody needs — delete the block `_template` ships with. Where it applies (HR is
the case it was built for), `defineCapabilities` declares named sub-features with dependencies, and
three rules follow:

- A capability is not a permission. A permission asks whether *this person* may; a capability asks
  whether *this workspace* has the feature at all. The answer for a disabled one is **404, not
  403** — `forbidden` claims the surface exists and is being withheld, which is false, and it
  contradicts a shell that has already hidden the navigation.
- Middleware order is `workspaceScoped` → `requiresCapability` → `requires`, so a workspace with the
  whole module off is refused before anything reveals which capabilities it would have had.
- Switching one off must never destroy data. It is a flag in module settings; anything that would
  need a migration to reverse is not a capability. That is the test.

A missing `requiresCapability` is invisible — the procedure compiles, the tests pass, and the only
symptom is a workspace calling a feature it switched off. List every gated procedure in
`<id>CapabilityProcedures` so `module.test.ts` fails when one loses its middleware. On the client,
`capability:` on a nav item, route, command, sidebar, widget or settings page is filtered exactly
like `permission`. See `docs/adr/0007-module-capabilities.md`.

## 4. Schema and migrations

```bash
pnpm --filter @kernhq/module-<id> db:generate   # drizzle → migrations/0000_init.sql
```

Generated SQL never contains RLS. Write `migrations/0001_rls.sql` by hand using `rlsPolicySql` for
every tenant table, the way `packages/tracker` does. Every tenant table carries `workspace_id` and a
composite index starting with it. `CREATE SCHEMA IF NOT EXISTS` — the kernel creates the schema
before migrating and the bare form fails on boot. Migrations are append-only once pushed.

## 5. Server module

`defineServerModule` with the definition, schema, `migrationsFolder`, router, subscriptions and jobs.
Every declared procedure implemented, every one authorised, every mutation emitting its event *and*
`kernel.realtime.change`. That is the `kern-service` skill's territory — work through it there rather
than trusting this list.

## 6. Client module

The manifest contributes nav, routes, commands, widgets, settings pages, slots and presenters. The
shell renders whatever is registered and knows nothing else about you.

**It all lives in the package** — `src/client/module.ts`, `pages/`, `widgets/`, `i18n.ts`. The app
holds no screens belonging to a module, and deleting the package removes the feature completely
(ADR 0008). There are no route files in the app to keep in step: declare a route and it is mounted.

- **Register it**: one import plus one `registerModule(...)` in `app/src/lib/modules/registry.ts`,
  from `@kernhq/module-<id>/client`. With `featureModules` in a host service that is the only wiring
  outside the package. A module that is not registered has no navigation and no routes, however
  complete the package is.
- **Strings live in `src/client/i18n.ts`**, namespaced by module id, one bundle per locale. Paraglide
  compiles the *app's* catalogue and cannot see you. A counted message is a map of CLDR plural
  category to string — English has two forms, Arabic has six. Shared words (Save, Cancel, Retry)
  come from the framework's `common` bundle; do not copy them.
- **Everything the shell provides comes from `@kernhq/ui`.** Stateless things are exported (`t`, the
  formatters, query `keys`, `uploadFile`, components, charts); stateful things are read from a
  singleton the shell fills (`session`, `navigation`, `getHost`).

Three mistakes compile while you edit inside the app and fail the moment the package builds alone.
All three shipped, in three different modules:

- **`$app/state` / `$app/navigation`** do not exist in a package. A route component is given
  `workspaceId`, `workspaceSlug` and `params`; anything else asks `navigation`.
- **Importing your own barrel** (`./index.js`) is a cycle — and the barrel reaches the manifest,
  so a pure-function test going through it dies with `$state is not defined`. Name the file.
- **A local called `t`** shadows the message function. `(t) => t('x')` type-checks as a property
  access on whatever `t` is. Six of these were in tracker alone.

- Then the `kern-ui` skill before calling any screen done.

## 7. Host it

Feature modules with no runtime reason to be alone are hosted by core:

```ts
// repos/core/src/service.ts
const featureModules = [trackerModule, <id>Module]
```

Add `"@kernhq/module-<id>": "^x.y.z"` to that service's `package.json` — a **published version**, never
`workspace:*`, which only resolves inside the umbrella workspace and breaks standalone CI.

Which workspaces see it is a runtime decision (`workspaces.modules.list`), not a code one. Shipping a
module does not force it on anyone.

## 8. Ship it

```bash
pnpm changeset                 # in repos/modules — write it alongside the change
pnpm check:pack                # packs for real and follows every relative client import
```

Push to `main`; `publish.yml` versions and publishes. Then bump the consumers (core, app) to the
version that actually exists on the registry — `npm view @kernhq/module-<id> version` — and push
those. The `kern-release` skill covers the ordering and the traps.

If the module adds environment variables or a container, `selfhost/docker-compose.yml`,
`selfhost/Caddyfile` and `selfhost/.env.example` change in the same breath, and `docs/` gets a page.

## 9. Verify by running it

```bash
pnpm infra && pnpm db:migrate && pnpm dev
curl -s localhost:4000/api/health
# then the real flow through the UI, signed in, with the module enabled for the workspace
```

Then `pnpm lint && pnpm typecheck && pnpm test && pnpm build` at the umbrella root.

Report what you exercised and what you did not. A module that has never served a request is not done,
whatever the type-checker says.

## The wiring checklist

A new module is reachable only when **all** of these are true. Check them off explicitly:

- [ ] package published, not `private`, `files` covers the client's imports
- [ ] contract, permissions, events declared and implemented
- [ ] capabilities declared and gated, or the `_template` block deleted — never left half-wired
- [ ] `mod_<id>` schema, RLS migration, tenant isolation test
- [ ] imported into a host service's module list
- [ ] screens, strings and manifest in `src/client`; nothing of this module in the app
- [ ] registered in `app/src/lib/modules/registry.ts` (one line)
- [ ] `pnpm --filter @kernhq/module-<id> typecheck` passes — it checks the client too
- [ ] widgets declared, or a sentence saying why the module has none (`kern-widget`)
- [ ] messages in en, fa, ar, de
- [ ] changeset written, consumers bumped to a published version
- [ ] selfhost + docs updated if the surface changed
- [ ] any platform capability this module needed and did not find: added through `kern-platform`,
      with `_template`, the generator and the other modules moved with it — not faked locally
