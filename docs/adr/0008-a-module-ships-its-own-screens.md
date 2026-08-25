# ADR 0008 — A module ships its own screens

- Status: accepted (2026-08-25)
- Context: every module's interface lived in the `app` repository. `@kernhq/module-tracker` shipped
  13 client files while its ~16,800 lines of screens sat in `app/src/lib/modules/tracker`, and 30 of
  the application's 56 pages belonged to a module. The client-module contract already declared
  `routes`, `messages` and `defaultHost`, and nothing read any of them.

## The problem, stated precisely

ADR 0005 put `_template` and the framework on the Apache-2.0 side so that anybody could write a
closed Kern module. That promise was structurally undeliverable:

1. **A third party could not ship a screen.** Routing was the application's SvelteKit file tree, so
   contributing a page meant editing an AGPL-3.0 repository they do not own.
2. **A module's strings could not travel with it.** Paraglide compiles the application's
   `messages/*.json`; a module shipping separately is invisible to it.
3. **A module was never type-checked as a unit.** The application compiled the screens, so `hr` had
   no client type-check at all, and defects that only appear outside the app — a barrel cycle, a
   `$app/state` import, a local shadowing the message function — could not be seen.
4. **Two halves drift.** `quire` had two hand-written copies of its permission keys, one in the
   package and one in the app, and they disagreed: the package's was missing `page.comment` and
   `page.publish` entirely. A wrong permission string is a perfectly valid string, so nothing
   reported it.

## Decision

**A module is one package.** Contract, server, screens, strings and manifest ship together. The
application holds the shell — a rail, a sidebar frame, a command palette, a dashboard grid, a
router — and no screens belonging to a module. Deleting a module package removes the feature
completely; that is the test of whether something is a module.

The wiring outside a module package is two lines: `featureModules` in a host service, and
`registerModule` in the application's registry.

### The seam

A module cannot import the application. Everything its screens need comes from `@kernhq/ui`, and the
line is:

> **Stateless things are exported; stateful things are read from a singleton the shell fills.**

Exported: `t` and the formatters, the query keys, `uploadFile`, the design-system components, the
charts, the mention and emoji helpers. Filled by the shell: `session` (identity, permissions, the
workspace's resolved capabilities), `navigation` (location, `go`, `describe`) and `Host` (a
configured API client, the API and collab origins, whether the mock is running).

One copy of `@kernhq/ui` in a tree is therefore load-bearing rather than tidy — two would mean the
shell and a module disagreeing about who is signed in. `pnpm.overrides` pins it, and now pins every
module package too.

### Routing

`ClientRoute` is mounted. A declaration may name parameters (`/quire/:space/:page`), and the winner
is the declaration with the most **literal** segments, length breaking the tie — so `/quire/settings`
beats `/quire/:space` and a space somebody named "settings" cannot shadow a real page. Settings pages
and instance-console pages mount from their declaration at conventional URLs.

### Strings

A module carries bundles keyed by locale and namespaced by module id; the shell merges them when it
registers the module. A counted message is a map of CLDR plural category to string, selected by
`Intl.PluralRules` — not a string with `{count}` in it, because English has two forms and Arabic has
six. Words every module needs and none owns — Save, Cancel, Retry — live in one `common` bundle
rather than being translated six times.

## Consequences

- **Editing a module's screens is a publish round trip** for the consumer's CI. Locally the
  workspace link keeps it live; CI installs from the registry. This is the price, and it is paid so
  that a module can come from outside this organisation.
- **The application's catalogue shrank from 1,725 keys to 755** — what is left is the shell's own.
- **Each module package type-checks its own client.** That is what surfaced the barrel cycles, the
  router imports and eleven shadowed `t` parameters across three modules, none of which the
  application could show.
- **`_template` is a whole module** and is published, so the Apache-2.0 promise is now reachable
  rather than merely stated.
- **A module that needs something the seam does not offer is a platform change**, not a reason to
  reach into the application: widen `@kernhq/ui`, roll it across `_template` and every module, and
  record it. See the `kern-platform` skill.
