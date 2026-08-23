# ADR 0003 — Billing, entitlements, and where Kern Cloud lives

- Status: accepted (2026-08-23)
- Context: `kernaio.com/pricing` sells Cloud Team at $8/user/month and Cloud Business at $16, every
  call to action points at `app.kernaio.com/signup`, and `LAUNCH.md` blocks the domain on that host
  accepting sign-ups. Meanwhile the workspace contained no occurrence of `stripe`, `billing`,
  `subscription` or `entitlement`; `docs/PLAN.md` reserved `KernAIO/cloud` as "out of v1 scope", and
  ADR 0002 §7 already promised a cloud that tracks stable releases. The question behind all of it:
  is Kern Cloud a separate product, or the same one with a switch turned on?

## Decision

**1. The same image. Billing is a public module, not a private fork.**

`@kernhq/module-billing` ships in the ordinary Kern image, alongside the tracker, and does nothing
until an instance gives it a plan and a Stripe key. Kern Cloud is that image with our keys set. The
public image *is* the cloud image.

The alternative — a private module compiled into a build only we make — was rejected. Module clients
are compiled into the app bundle (ADR 0002 decision 1), so a private module means a second build
variant, and a second build variant is a thing that drifts from the one everybody else runs. We would
find out it had drifted from a customer.

Publishing it costs nothing that was ever a moat. Anyone can already host Kern; billing code is not
what stops them. What an operator cannot copy is that we run it. And a self-hoster who sets their own
Stripe key can sell seats on their own instance — which is a feature against Plane and Huly, not a
leak.

**2. Core does not know who sells anything. It asks the kernel.**

Core hosts modules and therefore cannot import one. It calls `kernel.entitlements`, a facility shaped
exactly like the existing `Settings`: a broker call with a short cache. When no module answers
`billing.entitlements.get` — every self-hosted instance, on every request — every workspace is
unlimited. That is the default path, not an error path, and it cannot throw.

**3. Plan *values* are data. Plan *keys* are not.**

An instance admin creates plans in Admin → Plans, sets what each costs and what it allows, and
publishes. `GET /api/billing/plans/public` serves the published ones unauthenticated, and the
marketing site generates its pricing page from that endpoint, so a price is edited once and is true
both on the page and on the invoice.

What a plan may limit is fixed by the contract — seats, storage, modules, SSO, audit retention, API
rate — and each key has exactly one place in core that enforces it. An admin can invent a plan; an
admin must not be able to invent a limit that nothing checks, because that is precisely how this
project's pricing page came to promise storage quotas and SSO gating that did not exist.

**Adding an entitlement key means adding its enforcement site in the same commit.**

**4. A seat is a member who is not a guest.**

Guests are free. A guest is invited to look at one project or one channel, and charging for that
prices a workspace out of the collaboration guests exist for.

Seats are **recounted**, never adjusted by a delta: `core.member.removed` does not say what role the
person had and `core.member.updated` does not say what role they had *before*, so neither event can
be turned into arithmetic that is right. Storage does use deltas, because summing a workspace's files
on every upload is a scan — and a nightly job recounts and **logs** the drift rather than silently
correcting it, because silent correction hides the bug that caused it.

**5. Most of `mod_billing` is deliberately not row-level secured.**

A subscription is the instance operator's record *about* a workspace, not the workspace's own data.
The console that lists every workspace and the jobs that enumerate them cannot run under a policy
that returns nothing when `app.workspace_id` is unset. `plans`, `subscriptions`, `workspace_usage`,
`overrides` and `webhook_events` are operator tables, isolated in the procedure layer; `invoices` is
the customer's own record and is a proper tenant table with RLS.

This is the one place Kern's "every tenant table carries RLS" rule does not apply, and the reasoning
is written at the top of `src/server/schema.ts` where somebody changing it will read it.

**6. A failed payment starts a clock; it does not close the workspace.**

`past_due` still entitles. A grace period ends, and only then does the workspace become `suspended` —
which is read-only. A customer who has stopped paying can always still read and export what is
theirs.

**7. Refunds, tax, dunning mail and revenue reporting stay in Stripe.**

The admin console links into the Stripe dashboard rather than reimplementing it. What lives in Kern
is what an operator cannot get from Stripe: which workspace is on which plan, what it is using, and
the ability to comp, suspend or correct it.

**8. `KernAIO/cloud` holds the deploy pipeline and nothing else.**

Not a module, not a fork, no product code. Provisioning, regions, backups and the rollout ADR 0002 §7
described. Everything a person sees is in the public repositories.

## Consequences

- The comparison table on `/pricing` is now a set of claims that can be checked: SSO, storage and
  audit retention are real entitlement keys, and `LAUNCH.md` says so.
- `ClientSettingsPage.scope` gained `instance`, so the admin console takes module-contributed pages
  instead of the app hand-mounting each route. The console had exactly one page before this.
- Core gained `core.file.deleted`; without it any byte counter only ever grows. `core.file.ready`
  carries an optional `size` — optional so a rolling deploy, where an older core emits alongside a
  newer consumer, does not drop the event on validation.
- SSO registration is now refused when a plan does not include it. It is still not gated on
  *permission* — any member of an entitled workspace can register an identity provider. That was
  already true, it is marked `TODO` in `src/auth/auth.ts`, and it is a security follow-up rather than
  part of this ADR.
- Card is taken up front, so `app.kernaio.com` cannot accept a customer until live Stripe keys are
  in. There is no free-beta path in this shape; that was a deliberate choice.
