# Kern — modularity & hardcoding audit: consolidated findings

Merged from two independent audits, every item re-verified against the working tree.
Paths are relative to `kern/repos/` unless noted. Run each `Verify` from `kern/repos/`.

> **STATUS — 2026-08-25, re-checked against the live worktree.**
> P0/1 and P0/2 are **already fixed**, uncommitted, by another session sharing this worktree.
> Steps toward the per-module-UI migration are **in flight** in the same worktree:
> `app/src/lib/modules/routing.ts`, `app/src/routes/(app)/[ws]/[...module]/`,
> `app/src/routes/(app)/[ws]/settings/[...page]/`, `kernel/packages/ui/src/lib/settings/`.
> **Do not edit those paths without coordinating** — `git checkout` on them destroys uncommitted work.
> Findings 3-24 were unaffected and stand as written.

Status key: `[ ]` unverified by you · `[x]` confirmed · `[~]` disputed · `[-]` not reproducible

---

## P0 — broken right now, blocks everything downstream

### 1. [x] The app is loading registry copies of quire and tracker, below its own declared range
`app/node_modules/@kernhq/module-{quire,tracker}` resolve to `.pnpm/…@0.4.1` and `…@0.9.2` while
`app/package.json` declares `^0.6.1` and `^0.10.1`. The resolutions do not even satisfy the ranges —
the lockfile entries are corrupt, not merely stale. Every edit to those two module clients has been
invisible to the app. chat, mail, hr and billing are correctly linked to `repos/modules/packages/*`.

**Consequence:** any conclusion drawn from running the app about quire or tracker is unsound.

Verify:
```
for m in quire tracker chat mail hr billing; do
  echo "$m -> $(readlink app/node_modules/@kernhq/module-$m)"
done
```

### 2. [x] Six stale cross-repo dependency ranges — the duplicate-kernel trap, armed in CI
```
core  @kernhq/module-hr     ^0.1.0   workspace 0.4.0
core  @kernhq/module-quire  ^0.2.0   workspace 0.6.1
chat  @kernhq/contracts     ^0.2.0   workspace 0.5.1
chat  @kernhq/kernel        ^0.2.0   workspace 0.6.0
mail  @kernhq/contracts     ^0.2.0   workspace 0.5.1
mail  @kernhq/kernel        ^0.2.0   workspace 0.6.0
```
A caret on 0.x never crosses a minor, so standalone CI installs a second `@kernhq/kernel` and two
structurally distinct `ServerModule` declarations. Masked locally by `pnpm.overrides`.
`collab` and `app` are clean. This is the exact failure documented in `kern/CLAUDE.md`.

Verify: compare each repo's `package.json` `@kernhq/*` ranges against
`modules/packages/*/package.json` and `kernel/packages/*/package.json` versions.

---

## P1 — correctness, and violations of the project's own written rules

### 3. [x] Event subscriptions are stringly-typed with an unchecked payload cast
`kernel/packages/kernel/src/module.ts:131` — `subscriptions?: Record<string, EventHandler<any>>`.
The key is a bare string and handlers do `event.payload as {...}`
(e.g. `modules/packages/tracker/src/server/index.ts:290-291`). A typo'd event name compiles,
registers, and silently never fires. Nothing validates the name against any emitter's declared
`events`, and nothing validates the payload shape.

### 4. [x] `apiRateLimit` entitlement has no enforcement site
`kernel/packages/kernel/src/http.ts:154` registers a static `max: 600` per minute for everyone.
`modules/packages/billing/src/contract.ts:32` lets an admin set a per-plan value. Nothing reads it.
Violates the rule in `CLAUDE.md`: "an entitlement key without an enforcement site is a lie."

Verify: `grep -rn "apiRateLimit" --include='*.ts' . | grep -v node_modules | grep -v dist`
— expect only the declaration, the contract, and tests.

### 5. [x] `auditRetentionDays` entitlement has no enforcement site
No prune job exists anywhere. Same rule violated.

Verify: `grep -rn "auditRetention\|prune" core/src --include='*.ts' | grep -v test`

### 6. [x] `requireActive()` has zero production callers
`kernel/packages/kernel/src/entitlements.ts:132`. A suspended or past-due subscription currently
refuses no writes.

Verify: `grep -rn "requireActive" --include='*.ts' . | grep -v node_modules | grep -v dist`
— expect only the definition and its own unit test.

### 7. [x] The mail module's settings link 404s
`app/src/lib/modules/mail/client.ts:88` declares `id: 'mail'`, so the shell builds
`/<ws>/settings/mail/mail`. The page is at `/<ws>/settings/mail`. Already noted in `app/CLAUDE.md`
and still shipping.

Verify: every workspace-scope `settingsPages[].id` must have a route at
`app/src/routes/(app)/[ws]/settings/<moduleId>/<pageId>/+page.svelte`. mail is the only failure;
the other 13 pass.

### 8. [x] Permission keys are hand-copied literals in four app modules
`app/src/lib/modules/{tracker,chat,quire,mail}/permissions.ts` re-declare string literals the
module contracts already declare (e.g. `tracker.issue.edit_any`). A typo silently hides or shows a
control and nothing catches it. `app/src/lib/modules/hr/permissions.ts:1` does it correctly —
it re-exports `HR_PERMISSIONS` from `@kernhq/module-hr/client`. The fix pattern already exists.

### 9. [x] Server-supplied English bypasses i18n on two admin screens
- `app/src/routes/(app)/[ws]/settings/roles/+page.svelte:205,210` renders `{permission.label}`
- `app/src/routes/(app)/[ws]/settings/modules/+page.svelte:134,155,209` renders
  `{entry.manifest.name}` / `.description`

Both come from hardcoded English in the module contracts
(`modules/packages/tracker/src/contract/permissions.ts` and each module's manifest). The roles and
modules screens are therefore English-only in fa, ar, de and tr, against the rule that all
user-facing strings go through Paraglide. The app's own strings are clean — 1694 keys, identical
count in all five catalogues, ~9 hardcoded strings across ~290 files, all demo/placeholder text.

---

## P2 — modularity gaps and hardcoded policy

### 10. [x] `ClientRoute` and `defaultHost` are declared and never read
`ClientNavItem`/`ClientRoute` in `kernel/packages/kernel/src/client/index.ts`; `defaultHost` in
`kernel/packages/kernel/src/module.ts:103`. Client modules populate `routes:`
(`app/src/lib/modules/tracker/client.ts:35`, `chat:88`, `quire:33`, `hr:41`) and nothing consumes
them — routing is entirely SvelteKit's file tree, and each `app/src/lib/modules/*/api.ts` hardcodes
its service port rather than deriving it from `defaultHost`. A declared-but-unread extension point
reads as a promise. Either mount them or delete them from the contract.

Verify: `grep -rn "\.routes\b" app/src kernel/packages/ui/src --include='*.ts' --include='*.svelte'`
— expect only comments.

### 11. [x] The capability middleware guard covers 3 of 8 module packages
Re-grepped 2026-08-25: `_template` (2 sites), `hr` (3), `quire` (2) have the
`middlewares?.length` check — even thinner than first counted; conclusion unchanged.
`billing`, `chat`, `mail`, `tracker`, `workflow` have none — including tracker, the largest module.
One audit described this guard as platform-wide; it is not. Forgetting `requiresCapability` on a
tracker or chat procedure fails nothing.

Verify:
```
for m in _template billing chat hr mail quire tracker workflow; do
  echo "$m: $(grep -rc 'middlewares?.length' modules/packages/$m/src 2>/dev/null | awk -F: '{s+=$2} END{print s+0}')"
done
```

### 12. [~] The UX guard covers 32 of 50 static routes
`app/tests/e2e/ux.spec.ts` `ROUTES`. Partially wrong as written: `/sign-in`, `/sign-up`,
`/forgot` and `/workspaces` ARE swept (`ux.spec.ts:56-59`). Confirmed unswept: all 11 HR routes
(`/WS/hr`, `/WS/hr/{approvals,attendance,leave,offices}`,
`/WS/settings/hr/{calendars,capabilities,leave,offices,schedules}`) plus `/reset`, `/two-factor`,
`/onboarding` and `/`. `CLAUDE.md` says adding a route means adding it there; HR was added without.

### 13. [x] The SSR fallback URL is copy-pasted across nine files, and the generator propagates it
`env.PUBLIC_API_URL || (browser ? window.location.origin : 'http://localhost:4000')` appears in
`app/src/lib/api/client.ts:30`, `app/src/lib/auth/client.ts:13`, and six
`app/src/lib/modules/*/api.ts` (ports 4000/4100/4200, plus `ws://localhost:4300` in
`quire/components/PageEditor.svelte:50`). `modules/scripts/new-module.mjs:180` stamps the pattern
into every future module. One missed env var is a silent SSR connection refusal.

### 14. [x] Three upload limits that disagree
- `kernel/packages/kernel/src/http.ts:126` — `bodyLimit: 25 * 1024 * 1024`, platform-wide, not tunable
- `core/src/env.ts:41` — `UPLOAD_MAX_PUT_BYTES` default 500 MB
- `app/src/lib/modules/chat/components/Composer.svelte:72` — `MAX_UPLOAD_BYTES = 100 * 1024 * 1024`

### 15. [x] A disabled module answers 403; a disabled capability answers 404
`kernel/packages/kernel/src/errors.ts:41` maps `MODULE_DISABLED` to 403.
`kernel/packages/kernel/src/http.ts:69-84` (`requiresCapability`) throws `NOT_FOUND`.
The written rule in `CLAUDE.md` and ADR 0007 is about capabilities and is honoured — this is an
open design inconsistency rather than a broken rule, but the ADR's reasoning ("it contradicts a
shell that already hid the navigation") applies equally to a module switch. Decide and record it.

### 16. [x] The instance cannot be renamed through any documented surface
Two unrelated variables: `PUBLIC_INSTANCE_NAME` (`app/src/lib/auth/client.ts:28`) and
`KERN_INSTANCE_NAME` (`mail/src/env.ts:17`, `modules/packages/mail/src/server/send.ts:12`).
Neither appears in `kern/selfhost/.env.example` (57 lines, no name key) or the compose files.
`core/src/auth/auth.ts` hardcodes `appName: 'Kern'` (:54), `issuer: 'Kern'` (:164),
`rpName: 'Kern'` (:165), so a self-hoster's authenticator app and passkey prompt say "Kern"
regardless of what they set.

### 17. [x] `RESERVED_SLUGS` hand-mirrors the app's route names across a repo boundary
`core/src/modules/core/services/workspaces.ts:27`. Correct today; nothing keeps it correct. A new
top-level app route creates a workspace slug that exists and never opens, failing nothing.

### 18. [x] Event retention is baked into stream creation
`kernel/packages/kernel/src/events/nats.ts:73` — `max_age: 7 * 24 * 3600 * 1e9`, not an env var.

### 19. [x] Remote-module settings validation is an open TODO
`core/src/modules/core/services/modules.ts:226` — zod validation only when the module is hosted in
this process; remote modules are unvalidated pending an ajv path. Relevant to the third-party
module story.

### 20. [x] The module UI lives in the host app, not in the modules
```
app/src/lib/modules/     27,965 lines   module UI, inside the AGPL app
modules/*/src/client/     2,898 lines   what the module packages ship
30 of 56 app pages belong to a module
5,659 lines of mock re-implement every module API, with no test that the two agree
```
`@kernhq/module-tracker` ships 13 client files; its ~16,800 lines of interface sit in `app/`.
Adding a module touches 3 repos: package in `modules` → one array line in `core/src/service.ts:37`
→ client manifest + `registerModule` in `app/src/lib/modules/registry.ts` + one hand-written
SvelteKit route per screen + a `mock.ts` entry + five i18n catalogues + `ux.spec.ts`.
Nothing checks that any of those happened.

This is a real constraint on the Apache-2.0 closed-module promise: a third party can ship the
headless half from `_template` alone, but cannot ship a screen.

---

## P3 — low

- `modules/packages/billing/src/server/services/stripe.ts:22` — `appInfo: { url: 'https://kernaio.com' }`
  reported by every self-hosted instance
- `kern/cloud/docker-compose.yml:38,130` — `MAIL_FROM` and `KERN_ADMIN_EMAIL` default to `kernaio.com`
- `kern/dev/compose.yml:26,33` — MinIO password `kernkernkern` duplicated in two places
- `modules/packages/billing/src/server/index.ts:34` — `core.workspaces.list` with `limit: 10_000`,
  a silent ceiling
- Port allocation is stated in three places: `vite.config`, `package.json` scripts, `CLAUDE.md`

---

## Confirmed clean — do not re-litigate

These were checked and hold. Re-verify if cheap; do not report as findings without new evidence.

- **Data isolation is airtight.** Zero `@kernhq/module-*` imports between module packages. Every
  module names only its own schema: chat 17× `mod_chat`, hr 26× `mod_hr`, quire 16× `mod_quire`,
  tracker 10× `mod_tracker`, billing 3× `mod_billing`. No foreign-schema query anywhere.
- **`kernel.call()` is service-agnostic.** `kernel/packages/kernel/src/call.ts` routes
  `<module>.<procedure>` in-process or over `kern.rpc.*` with no service names in it.
- **The shell is generic.** Outside `app/src/lib/api/mock.ts`, `app/src/lib/` contains zero
  references to `'tracker'`, `'chat'`, `'hr'`, `'quire'` or `'billing'`. `registry.ts` derives nav
  (:59), sidebars (:83), widgets (:105), commands (:126) and settings links (:164) from manifests.
- **Manifest versions are all derived.** `packageVersion(import.meta.url)` in all seven module
  packages plus `CORE_VERSION` (`core/src/modules/core/index.ts:37`). No literals.
- **Design tokens are honoured.** 16 literal colours in the whole app, in 2 files.
- **App i18n is complete.** 1694 keys × 5 locales, identical counts.
- **No committed secrets, no machine paths, no `files.` hostnames in source.**
- **Enforced entitlements:** `seats` (`core/src/modules/core/services/invitations.ts:90,242`),
  `storageBytes` (`core/src/modules/core/services/files.ts:67`), `modules`
  (`core/src/modules/core/services/modules.ts:115`), `sso` (`core/src/auth/auth.ts:126`).

---

## Notes for the re-check

Two things worth adversarial attention, because they are where the previous audits were weakest.
**Both re-checked 2026-08-25**: (1) still true that nothing was run — findings 7, 9 and 12 remain
static predictions, though all three now re-verified against source; (2) resolved above — finding 11
confirmed (thinner than counted), finding 12 partially wrong about pre-login coverage.

1. **Neither audit ran the app or the test suites.** Everything above is static plus filesystem
   state. Findings 7, 9 and 12 predict user-visible behaviour that has not been observed.
2. **One prior claim was materially overstated** — that middleware-count assertions guard
   capability gating platform-wide (see finding 11: 3 of 8). Treat confident architectural
   generalisations in either report as unverified until re-grepped.

Suggested fix order, dependency-first:
1. Bump the six ranges in finding 2 **before** reinstalling.
2. Drop the quire/tracker lockfile entries (do not refresh — 0.4.1 does not satisfy `^0.6.1`),
   reinstall, and confirm with `readlink`, not by assumption.
3. Findings 4, 5, 6 — enforce or delete.
4. Finding 13 — one shared helper, and fix the generator so it stops propagating.
5. Findings 7, 8 — add `check-permissions.mjs` and a settings-route check to `pnpm lint`;
   both bug classes die permanently.

---

## The per-module-UI migration — agreed plan

**Decision (2026-08-25):** module UI moves out of `app/` and into each module package, applied to
all six modules and `_template`. Accepted cost: a module UI edit becomes a publish round-trip for
the app's CI (already documented in `app/CLAUDE.md`).

Order, dependency-first. Steps 1-3 are done or in flight; 4-7 are unclaimed.

1. ~~Unblock: ghost links + ranges~~ — **done** (findings 1, 2).
2. **Host contract** — *in flight.* Module clients currently reach 30+ app internals; those must
   become a published surface. Weighted by use:
   `$msg` 104 · `$lib/state/session.svelte` 34 · `$app/state` 25 · `$lib/format` 23 ·
   `$lib/api/client` 19 · `$app/navigation` 12 · `$lib/query` 9 ·
   `$lib/paraglide/runtime` 9 · `$lib/dashboard/WidgetState.svelte` 9 · `$lib/realtime.svelte` 8 ·
   `$app/environment` 8 · `$env/dynamic/public` 7 · then files, mentions, emoji, charts.
   `$lib/*` and `$msg` are SvelteKit aliases — they do not resolve inside a package. This is the
   whole difficulty of the migration.
3. **Mount `ClientRoute`** — *in flight* (`routing.ts` + two catch-alls). Without this, moving UI
   changes nothing: pages still need hand-written app route files.
4. **Wire `messages`** — *unclaimed.* `client/index.ts:262` declares
   `messages?: Record<string, () => Promise<Record<string,string>>>`; nothing populates or reads it.
   `modules/packages/chat/src/client/i18n.ts` already contains a written bundle (~60 keys) and a
   comment describing the intended merge, beside empty `components/` and `lib/` directories — this
   migration was started once and abandoned. Read that file before designing anything new.
5. **Migrate, module by module** — *unclaimed, nothing moved yet.*
   Current split (package client files vs app files):
   chat 5/26 · quire 3/15 · tracker 12/72 · hr 1/20 · mail 2/6 · billing 3/3.
   Suggested order: chat (bundle exists) → mail, billing → quire → hr → tracker (16,776 lines, over
   half the total; last whatever else is decided).
6. **`_template` + `modules/scripts/new-module.mjs`** — *unclaimed.* The generator currently writes
   the app half into `app/src/lib/modules/<id>/` and stamps the nine-file SSR fallback (finding 13)
   into every future module. Both must follow the new shape, or every new module recreates the
   problem being fixed.
7. **Record it** — ADR, `kern-module` / `kern-platform` skills, `CLAUDE.md`. The rule worth writing
   down: *a module ships its own screens, strings and routes; the app ships only the shell.*

**Related findings this closes:** 10 (dead `ClientRoute` / `defaultHost`), 13 (SSR fallback, via the
host contract), 20 (module UI in the host). **Does not close:** 8 (permission literals) or 9 (i18n
bypass) — both need their own fix, though 9 gets easier once modules own their strings.
