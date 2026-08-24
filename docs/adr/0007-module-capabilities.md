# ADR 0007 — Capabilities: the switch below a module

- Status: accepted (2026-08-24)
- Context: a module is the only granularity a workspace can switch. `workspace_modules.enabled` is a
  boolean, and the shell filters navigation, sidebars, widgets, commands and settings pages on it.
  That is the right size for chat, mail and the tracker, each of which is coherent only as a whole.
  It is the wrong size for HR, where one company wants a staff directory and nothing else, a second
  wants leave and approvals, and a third wants shift rosters and biometric clock-in. Three products
  under one name, and the boolean cannot express them.

## The problem, stated precisely

There were only three ways to ship a module that customers want different amounts of, and all three
are bad:

1. **Fork the code per customer.** Ends the "one application" claim on contact.
2. **Ship everything and let permissions hide it.** Permissions answer a different question — *may
   this person* — and every workspace still carries a navigation rail full of features it does not
   use. Worse, the honest failure for a feature a workspace never bought is not `forbidden`, and
   `forbidden` is all a permission can say.
3. **Split into many modules.** `hr`, `hr_leave`, `hr_attendance`, each its own npm package, its own
   Postgres schema, its own release. Real isolation, real cost: the daily attendance projection has
   to ask leave "was this person off that day" over `kernel.call()` on a hot path where a join would
   do, and every customer meets a module picker instead of a product.

## Decision

**1. A module may declare capabilities: named, dependency-aware sub-features a workspace switches.**

`defineCapabilities` in the contract half, so both server and client import the same objects. Each
carries an id, a label, `dependsOn`, `defaultEnabled`, a `level` for grouping the switchboard, and
`required` for the module's own foundation. It validates at import time — an unknown or circular
`dependsOn` fails when the module loads, not when somebody flips a switch.

**2. `resolveCapabilities` is the only implementation of the closure.**

Defaults applied, `required` forced on, and anything whose dependency is off pruned transitively —
switching `attendance` off takes `overtime` and `rosters` with it without either being named. Stored
keys the module no longer declares are ignored, so removing a capability in a release does not leave
a workspace holding a flag for something that is gone.

The server resolves; the client is *given* the resolved set on `WorkspaceModuleState.capabilities`.
A second implementation would eventually disagree with the first, and the way that disagreement
surfaces is a menu item whose API answers 404.

**3. A disabled capability is 404, not 403.**

This is the decision most likely to be argued with, so the reasoning is here rather than in a
comment. `forbidden` says *this exists and you may not have it* — correct for a person without a
role, and false for a workspace that never enabled the feature. It leaks the shape of a product the
customer did not buy, it contradicts a shell that has already dropped the navigation, and it turns a
hidden menu into an API that behaves as though something were being withheld. A capability that is
off means the surface is not part of this workspace's API, and that is what `notFound` says.

Middleware order is `workspaceScoped` → `requiresCapability` → `requires`. A workspace with the whole
module off is refused first, so the 403/404 distinction never reveals which capabilities the module
would have had.

**4. Switching one off never destroys data.**

Capabilities live under a reserved `$capabilities` key in the module's settings jsonb — the
platform's, not the module's, which is why a module's own settings schema never mentions them.
Switching one off writes one boolean. The tables stay, so switching it back on restores exactly what
was there. **Anything that would need a migration to reverse does not belong behind a capability**;
that is the test for whether something is a capability at all.

**5. The client half is one optional field, filtered where filtering already happens.**

`capability?: string` on `ClientNavItem`, `ClientRoute`, `CommandAction`, `SidebarContribution`,
`WidgetDefinition` and `ClientSettingsPage`. The shell's five accessors each gain one `.filter()`.
No conditional anywhere else, and a widget behind a disabled capability leaves the picker *and* any
layout that already placed it, because the dashboard already asks the registry what it may draw.

A contribution names its own module's capability unqualified (`'attendance'`); the shell namespaces
it (`hr.attendance`) because that is where several modules' capabilities meet.

**6. It is not a licence tier, and not an entitlement.**

`kernel.entitlements` says what a *plan* permits and is enforced in core. A capability is what a
workspace *chose*, and every self-hosted instance — where entitlements are unlimited by design — must
be able to switch things off. Conflating them would make the switchboard meaningless on exactly the
installations that most want it.

## Consequences

- Additive throughout. `ModuleManifest.capabilities` and `WorkspaceModuleState.capabilities` are
  defaulted, so every module published before this validates unchanged and reports none. An instance
  runs published module tarballs against a newer kernel on every update; that had to keep working.
- A missing `requiresCapability` is invisible — the procedure compiles and every other test passes
  while a workspace calls a feature it switched off. Each module therefore declares
  `<module>CapabilityProcedures` mapping capability to procedure as data, and `module.test.ts` fails
  when one named there is not carrying the middleware.
- `chat`, `mail`, `tracker` and `billing` declare none, deliberately. A capability nobody switches is
  a switch nobody needs, and the retrofit would be a change to shipped products for no customer.
- The obvious next argument is per-office or per-team narrowing, where one site has attendance and
  another does not. That is intentionally *not* decided here. If it happens it must only ever narrow
  what the workspace has on — widening would let a local admin grant a surface the workspace never
  bought, and would make the workspace switchboard a lie.
