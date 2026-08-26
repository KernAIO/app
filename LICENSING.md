# Licensing

Kern is open source. Two licences, and one rule that tells you which applies.

**The framework is Apache-2.0. The product is AGPL-3.0-only.**

If you are writing a module, you only ever touch the framework, so your module is yours to licence
however you like. If you are running or modifying Kern itself, the AGPL applies and your changes have
to be published.

## What is under which licence

### Apache-2.0 — the framework

Everything in the [`kernel`](https://github.com/KernAIO/kernel) repository, plus the two reusable
packages in `modules`:

| Package | What it is |
|---|---|
| `@kernhq/kernel` | Module host, broker, auth, storage, events, jobs, HTTP |
| `@kernhq/contracts` | Contract types shared between modules and services |
| `@kernhq/sdk` | Typed client for the Kern API and realtime socket |
| `@kernhq/ui` | The Ink/paper design system components |
| `@kernhq/testing` | Test harness for module authors |
| `@kernhq/tsconfig` | Shared TypeScript configuration |
| `@kernhq/module-template` | The template you copy to start a module |
| `@kernhq/workflow` | Generic state-machine engine for modules |

### AGPL-3.0-only — the product

| Repository | What it is |
|---|---|
| [`app`](https://github.com/KernAIO/app) | The web application |
| [`core`](https://github.com/KernAIO/core) | Accounts, workspaces, permissions, module host |
| [`chat`](https://github.com/KernAIO/chat) | Chat service |
| [`mail`](https://github.com/KernAIO/mail) | Mail service |
| [`collab`](https://github.com/KernAIO/collab) | Collaborative editing service |
| [`docs`](https://github.com/KernAIO/docs) | Documentation site |
| [`kern`](https://github.com/KernAIO/kern) | This repository — self-host distribution, docs, ADRs |
| `@kernhq/module-tracker`, `@kernhq/module-chat`, `@kernhq/module-mail`, `@kernhq/module-billing` | The first-party modules |

Each repository's `LICENSE` file is authoritative. Where a package inside a repository differs from
the repository root, it carries its own `LICENSE` — this is the case for `_template` and `workflow`
inside `modules`.

## What you may do

**Run it.** Self-host Kern for any purpose, commercial or not, for as many people as you like. You owe
us nothing and you do not need our permission.

**Change it.** Modify any part of Kern. If you distribute your modified version, or let other people
use it over a network, the AGPL requires you to publish those changes under the AGPL. That is the
whole of the obligation.

**Run it for other people.** The licences govern the code, not what you may charge for running it.
Two conditions apply when you operate Kern for others: publish your modifications under the AGPL, and
do not call it Kern — see [TRADEMARK.md](TRADEMARK.md).

**Write modules for it.** Yours, private, commercial, closed — all fine. See below.

## Modules

A module talks to Kern through `@kernhq/kernel`, `@kernhq/contracts`, `@kernhq/sdk` and `@kernhq/ui`.
All four are Apache-2.0, which means a module that uses them is **not** a derivative work of the
AGPL-licensed product, and you may licence it however you want — including keeping it closed and
selling it.

Start from `@kernhq/module-template`. It is Apache-2.0 for exactly this reason: if the template were
copyleft, every module copied from it would inherit that, and the ecosystem would be closed by
accident.

Two things do not get you this freedom:

- **Modifying the framework itself.** Change `@kernhq/kernel` and you are distributing a modified
  Apache-2.0 work; that is allowed, but you are on your own for support and it is a fork.
- **Modifying the product.** Change `core`, `app` or a first-party module and the AGPL applies to
  those changes, module or not.

**For maintainers:** a *first-party* module is AGPL-3.0-only and carries no `LICENSE` file of its own —
the repository root covers it. `scripts/new-module.mjs` copies the Apache-2.0 template, so it must
overwrite the licence field and delete the copied `LICENSE`; an Apache-2.0 first-party module gives
away the copyleft that makes the product's licence mean anything.

The boundary only holds if the Apache-2.0 packages are enough to write a complete
module. If a module author has to reach into an AGPL package to get something done, that is a bug in
the boundary, not a licensing question — move the API, do not move the licence.

## Contributions

Contributions are accepted under the [CLA](CLA.md), which grants KernAIO the right to relicense. That
is what makes the split above possible in the first place, and what lets us offer Kern Cloud.

Contribute to an Apache-2.0 package and your contribution is Apache-2.0. Contribute to an AGPL package
and it is AGPL. The file you are editing tells you which.

Dependencies must be MIT, Apache-2.0, BSD or ISC. Do not add a GPL, AGPL, SSPL or source-available
dependency to any package without raising it first — in an Apache-2.0 package it would break the
licence outright.

## If this ever changes

We do not intend to relicense Kern, and we have written down what would have to happen first.

If a third party operates a hosted Kern service with a material number of paying customers, we reserve
the right to ship future versions of the AGPL-licensed product under the
[Functional Source License](https://fsl.software). Every version released before that date stays
AGPL-3.0 forever — a licence already granted is not withdrawn. The Apache-2.0 framework stays
Apache-2.0 either way.

Saying this out loud now is the point. See
[ADR 0005](docs/adr/0005-licensing-and-the-module-boundary.md) for the full reasoning.

## Questions

Anything not answered here: <legal@kernaio.com>. If you are a company whose legal team needs something
in writing, say so and we will put it in writing.
