# ADR 0004 — The home page is composed of module widgets

- Status: accepted (2026-08-23)
- Context: The workspace home was the one screen nobody owned. It showed a greeting, unread
  notifications and three counts, and had not changed since the shell was first committed, while
  `DESIGN.md` §3.1 described something considerably richer. Meanwhile `SlotName` carried a
  `dashboard.widget` member with no contributors and no consumers, and `messages/en.json` carried an
  orphan `home_widgets` key — two fossils of a dashboard that had been intended and never built.
  Every module has something somebody would want on their home page, and no module had a way to put
  it there.

## Decision

**1. A widget is a catalogue entry on `ClientModule`, not a slot.**

`SlotContribution` says only "render this component here". A dashboard has to draw a picker from
what exists, validate a stored layout against what a widget allows, and generate a settings form —
none of which a slot carries enough information to do. So `dashboard.widget` is deleted from
`SlotName` (nothing contributed to it) and replaced by `widgets?: WidgetDefinition[]`, carrying
title, description, icon, permission, allowed sizes, and a declarative settings schema.

The shell owns the frame — card, header, drag grip, menu, and the loading, empty, error and
no-longer-available states. A module writes only a body. That is what keeps permission gating, drag
handling and design fidelity out of every module's code, and it is why a widget is never passed its
own title.

**2. The server resolves the policy; the client owns what a preset contains.**

`mod_core.dashboard_layouts` holds one row per person per surface, plus one row with a null
`user_id` for what the workspace hands out. `mod_core.dashboard_settings` holds the policy —
`locked`, `default` or `open` — and which preset applies. `dashboard.get` returns the resolved
answer so no client re-implements the table.

Presets themselves are **not** stored. A preset is a list of widget ids, and a widget id is a client
concept the server has never heard of; core stores *which* preset applies and the app expands it.
The cost is that `defaultPresetId` cannot be validated against a list, so the client falls back to
`my-work` for an id it does not recognise — a preset removed in a later release must not produce a
blank page. The benefit is that reshaping a preset stays an app-only change with no contracts-first
publish.

**3. `locked` is refused by the server.**

`dashboard.save` answers `CONFLICT` with `core.dashboard.locked` when the workspace has locked the
layout. Hiding the button is presentation; this is the policy. Setting the workspace layout reuses
`core.workspace.manage` rather than adding a key — whoever sets the workspace logo sets its home
page.

**4. Geometry is a pure module, and `items` is repaired on every read.**

`repos/shell/src/lib/dashboard/grid.ts` holds collision, compaction, move, resize and the responsive
projection, with no Svelte, no DOM and no `$msg` — a module that imports the message catalogue
cannot be unit-tested, and a dashboard breaks in its arithmetic far more often than in its markup.
The stored layout is always twelve columns; six and one are projections computed at render and never
written back. Because `items` is jsonb, which the database does not lay out, `normalise()` runs on
every read: a row written by an older image, a rolled-back one, or by hand must not be able to draw
two cards on top of each other.

- Consequences: A module gains a home-page presence by declaring `widgets`, and loses it completely
  when a workspace switches it off, with no conditional in the shell. `@kernhq/kernel`'s `SlotName`
  narrows, which is a type-level break carried by a minor version pre-1.0. Widgets are limited to
  what a module's contract already returns, which is deliberate: three proposed widgets were cut
  during the first implementation because nothing counted what they claimed to count.
