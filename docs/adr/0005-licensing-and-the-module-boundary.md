# ADR 0005 — Licensing: the framework is Apache-2.0, the product is AGPL

- Status: accepted (2026-08-24)
- Context: `docs/PLAN.md` set AGPL-3.0 for every public repository and left the question open until
  the first public release. Nothing has been released yet, so this is the last cheap moment to answer
  it. Four goals were stated: anyone can self-host, anyone can write modules — private, commercial or
  shared, anyone can contribute, and the hosted business should be ours. Reading the workspace against
  those goals turned up a contradiction: all twenty packages are `AGPL-3.0-only`, including
  `@kernhq/kernel`, and every module in `repos/modules` imports `defineModule`, `defineServerModule`,
  `KernError`, `requires`, `workspaceScoped`, `moduleSchema` and `uuidv7` from it. A third party
  writing a closed module for their own instance would be linking AGPL code and serving it over a
  network. The second goal did not actually work.

## Decision

**1. Two licences, split at the framework boundary.**

The `kernel` repository — `@kernhq/kernel`, `@kernhq/contracts`, `@kernhq/sdk`, `@kernhq/ui`,
`@kernhq/testing`, `@kernhq/tsconfig` — becomes **Apache-2.0**, together with
`@kernhq/module-template` and `@kernhq/workflow` in `repos/modules`.

Everything else stays **AGPL-3.0-only**: `app`, `core`, `chat`, `mail`, `collab`, `docs`, this
repository, and the first-party modules `tracker`, `chat`, `mail` and `billing`.

The rule is *framework versus product*, not *library versus application*. A competitor who wants to
host Kern needs the product, and the product is copyleft. Somebody building an unrelated thing on our
plumbing needs only the framework, and is welcome to it.

`@kernhq/ui` is on the Apache side deliberately. A module that cannot use the design system renders as
a foreign object inside the app, and a component library is not a moat. `@kernhq/module-template` is
on the Apache side because a copyleft template makes every module copied from it copyleft — the
ecosystem would have closed itself by accident, on line one, before anyone noticed.

**2. We do not stop anyone selling hosted Kern, because no open source licence does.**

The AGPL forces a competing host to publish their modifications. It does not stop them competing, and
it was never going to. Elastic, Redis and HashiCorp each learned this and each answered it by leaving
open source — every one of them after they were large, and after a hyperscaler had actually taken the
business. We are pre-1.0 and unknown, so our risk is obscurity, not Amazon.

This is also already our position: ADR 0003 shipped `@kernhq/module-billing` in the public image
precisely so a self-hoster can set their own Stripe key and sell seats, and called that a feature
against Plane and Huly. It still is. Forbidding it now would contradict a decision made yesterday.

**3. The name is what we hold back, and it is for sale.**

`TRADEMARK.md` reserves *Kern*, *KernAIO*, the mark and kernaio.com. Anyone may run and sell Kern;
they may not call it Kern. A **Kern Certified Host** may — listed on the site, early releases, a
support path — for a revenue share. That converts the people we were worried about into a channel,
and it is enforceable in a way a licence restriction on a pre-1.0 project would not be.

The mark needs registering, and *Kern* is a common word (kerning; German and Dutch for *core*), so the
registration may be narrow. That work is outstanding and this decision depends on it.

**4. The trigger for changing our mind is written down in public.**

If a third party operates a hosted Kern service with a material number of paying customers, future
versions of the AGPL side may ship under the Functional Source License. Versions already released stay
AGPL forever, and the Apache-2.0 framework stays Apache-2.0. `LICENSING.md` says this to everyone
rather than to ourselves — announcing the condition beforehand is what separates a planned move from
the relicensings that produced OpenTofu, Valkey and OpenSearch.

## Rejected

**EPL-2.0**, which prompted the review. It is the worst of the three for us: a competitor may host Kern
*and* keep their changes private, because its copyleft reaches only modified files. Huly chose it —
their platform is EPL-2.0 throughout, other companies ship products on it, and their own hosted
service announced its shutdown while this was being decided. The two facts may be unrelated; the shape
is still the one to avoid.

**FSL or BSL now.** Both deliver goal four outright and cost the words "open source" — which is the
README's first line, the reason to pick Kern over Linear, and the entry ticket to the directories and
app stores where self-hosted software is found. Decision 4 keeps the option without paying for it yet.

**A Commons Clause-style rider on the AGPL.** Neither AGPL nor open source, incompatible with our own
dependencies, and a legal mess in exchange for protection nobody would test. If the restriction is
ever wanted, take FSL cleanly.

**Extracting a module-authoring SDK and keeping `@kernhq/kernel` AGPL.** Structurally the tidier
answer: move `defineModule`, the `Kernel` interface, `KernError` and the guards into an Apache-2.0
package, leave `createKernel` and `createHttpServer` behind. It was rejected for now on cost — the type
graph reaches into settings, storage, events and jobs, and every import in eight repositories moves
with it. What made the cheaper answer acceptable is that `@kernhq/kernel` is plumbing: 2,551 lines of
broker, auth, database, events and HTTP. Building a competing workspace suite on it still means writing
the entire product.

- Consequences: `repos/kernel` is now an Apache-2.0 repository and `repos/modules` is mixed, so the
  root `LICENSE` is no longer the answer for every file in a repository — `_template` and `workflow`
  carry their own, and `LICENSING.md` is the map. A contributor's grant now depends on which package
  they edit. Relicensing Apache-2.0 code back to AGPL is not possible for versions already published,
  so the framework boundary is a one-way door: moving a package to the Apache side is a decision to
  make once and deliberately. Dependencies of an Apache-2.0 package must be permissive — the tree was
  audited and is clean today (`sharp`'s LGPL native binary and MPL-2.0 `lightningcss` are dependencies
  of the AGPL side, not incorporated source). The boundary is now a design constraint with teeth: if a
  module author has to reach into an AGPL package to get something done, the API moves, not the
  licence.
