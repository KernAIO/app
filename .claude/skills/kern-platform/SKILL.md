---
name: kern-platform
description: Change the module system itself — add, alter or remove an extension point in the kernel, update `_template` and the generator, and roll it across every module, service and app that already exists. Trigger when a feature needs something the module contract does not offer, when editing repos/kernel/packages/{contracts,kernel,ui} or repos/modules/packages/_template, when a rule in another kern skill is wrong for what you are building, or when a capability should be removed from the platform.
---

# Changing the platform itself

The module system is not fixed furniture. Most work is building *with* what the kernel offers; some
work is the kernel not offering something, and then the change is the kernel, the template and every
module that already exists — in one piece, not in one module's corner.

The other skills describe the platform as it is today. When your change makes one of them wrong, the
skill is part of the diff (§8). Do not contort a feature to fit a template that should have moved.

## 1. Decide: feature, or extension point?

Say which, in one sentence, before touching `repos/kernel`.

**Build with what exists** when the capability is already there under another name. Before concluding
it is missing, read the surface: procedures, events, subscriptions, jobs, automations (triggers /
conditions / actions), search indexers, object resolvers, settings schema, nav, routes, commands,
slots, presenters, widgets, notification renderers.

**Extend the platform** when either is true:
- two or more modules would otherwise hand-roll the same thing, or
- the module has to reach outside its boundary to get it — write another module's tables, patch the
  shell, import a service directly. That reach is the architecture telling you the kernel is short a
  seam, and working around it is how the boundary quietly dies.

**Do not extend it** for one module's convenience. A capability only `mail` will ever use lives in
`mail`. The kernel is Apache-2.0 and third parties compile against it (ADR 0005) — everything added
there is a promise to strangers.

## 2. Where the seams are

| Surface | File |
|---|---|
| Declared manifest (admin UI, CLI, `installed_version`) | `repos/kernel/packages/contracts/src/module.ts` |
| Server capability | `repos/kernel/packages/kernel/src/module.ts` — `ServerModule`, `ModuleDefinition` |
| The code that *consumes* the declaration | `repos/kernel/packages/kernel/src/{registry,kernel,http,jobs,realtime,authz}.ts` |
| Client contribution types | `@kernhq/kernel/client`, bound to Svelte in `repos/kernel/packages/ui/src/lib/module.ts` |
| The shell that renders it | `repos/app/src/routes/(app)/[ws]/+layout.svelte`, `lib/components/CommandPalette.svelte`, `lib/dashboard/*`, `lib/modules/ModuleSidebar.svelte` |
| The shape every module starts from | `repos/modules/packages/_template` |
| The generator | `repos/modules/scripts/new-module.mjs` (one package — there is no app half) |

**The client seam is `@kernhq/ui`, and widening it is platform work too.** A module's screens live
in its own package and cannot import the app (ADR 0008), so anything they need from the shell is
either exported from `@kernhq/ui` (stateless: `t`, formatters, query keys, components) or read from
a singleton the shell fills (stateful: `session`, `navigation`, `getHost`). A module reaching into
the app is a missing extension point, not a shortcut — and it will compile until the package is
built on its own.

A field added to `ServerModule` and read nowhere is decoration: every module that fills it in does
nothing, and nothing fails. Add the consumer in the same change as the declaration.

## 3. Additive by default

Released modules pin `@kernhq/kernel: ^0.x` and are **not** recompiled when the kernel changes. An
instance runs published module tarballs against a newer kernel image every single update.

- New `ServerModule` / `ClientModule` key → optional.
- New manifest field → `.optional()` or `.default(...)` in the zod schema. A required field makes
  every already-published module fail manifest validation *at boot*, including third-party ones.
- Widening a type, adding an enum member the old code ignores → fine.
- Renaming, narrowing, making required, changing a handler's arguments → breaking.

When it has to be breaking: land it as a kernel minor (we are 0.x), bump the dependency range in
`_template` and in every module, and set `minKernel` on any module that now needs the newer platform
so the kernel refuses to boot with a readable sentence instead of exploding later at an unrelated
call site. Guard it with a test beside `packages/kernel/src/module.test.ts`.

## 4. Removing a capability — reverse order

1. Stop using it: every package in `repos/modules/packages`, every host service, the app shell.
2. Remove it from `_template` and from `new-module.mjs`.
3. Mark it deprecated in the kernel and keep it working for one release.
4. Delete it from the kernel, and release.

Never delete the kernel side first. Modules resolve the **published** kernel in their own CI, so a
kernel release that drops something before its consumers stopped using it turns every module repo red
without a single module having changed.

If the capability owned tables, the data goes in a *later* release than the code that stopped writing
it — migrations are append-only and a rollback has to still read the schema (`kern-service` §5).

## 5. Roll it across what already exists — same change

A template that grew a section, plus five modules that never got it, is worse than not shipping the
feature: the next agent copies the template, sees `tracker` doing it the old way, and cannot tell
which is right.

```bash
cd repos/modules/packages
ls -d */                                             # _template billing chat hr mail quire tracker workflow
grep -rln "<the old thing>" --include='*.ts' . | grep -v node_modules
grep -rn "<the old thing>" ../../{core,chat,mail,collab}/src ../../app/src 2>/dev/null
```

Every directory in that `ls` gets an answer: wired up, or one line saying why this module does not
need it. Then the hosts — `repos/core/src/service.ts` and the other services' module lists — and
`repos/app/src/lib/modules/registry.ts`.

- [ ] contracts + kernel implementation + the code that consumes the declaration
- [ ] `@kernhq/contracts` / `@kernhq/kernel` released; ranges bumped in `_template` and every module
- [ ] `_template` shows the new shape — and is **released**, not just edited: it is a published
      package now (`@kernhq/module-template`), and it is what a third party outside this
      organisation copies. A template a release left behind teaches the old shape to everyone
      who starts after it.
- [ ] `new-module.mjs` generates it
- [ ] every existing module updated, or a stated reason
- [ ] host services and the app registry
- [ ] `selfhost/` and `docs/` if what a self-hoster configures or sees changed
- [ ] an ADR if the change alters what a module is *allowed* to do
- [ ] the skills that describe the old shape (§8)

## 6. Release order

Contracts, then kernel, then modules, then services and app — `kern-release` has the traps. The one
that is specific to platform work: a module cannot be released against an unpublished kernel.
`workspace:*` resolves inside the umbrella and nowhere else, so check what actually exists before
bumping ranges.

```bash
npm view @kernhq/kernel version && npm view @kernhq/contracts version
```

## 7. Verify with an old module and a new one

```bash
pnpm build && pnpm typecheck && pnpm test        # umbrella root
(cd repos/modules && pnpm check:pack && pnpm check:versions)
pnpm infra && pnpm db:migrate && pnpm dev
```

Then exercise it: a module that uses the new capability does the new thing, and a module that does
not still boots and behaves exactly as before. Both halves matter — the second is the compatibility
claim in §3, and it is the one nobody checks.

## 8. The skills are part of the diff

When the platform moves, whatever described the old shape is now a trap, because it is trusted:
`kern-module` (the nine steps and the wiring checklist), `kern-service` (the completeness bar),
`kern-ui`, `kern-widget`, `_template/README.md`, `docs/`. Update them in the same commit, delete what
stopped being true, and say out loud what you changed — `kern-improve` is the how.
