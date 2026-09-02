# ADR 0009 — Kernel and modules progress independently, and never combine unsafely

- Status: accepted (2026-08-26)
- Context: modules moved to their own repositories (2026-08-25), each with its own npm release. That
  raised the question ADR 0002 had deliberately closed for v1.0: if a module publishes a version that
  needs a kernel capability the currently-shipped platform does not have, what stops that combination
  from reaching an instance? Today, nothing does — `core`'s `package.json` pins each module's npm
  range by hand, and nobody re-checks compatibility when that pin moves. `@kernhq/kernel` is a plain
  `dependency` of a module, not a `peerDependency`, so npm install never questions whether the copy it
  hands the module is one the module was actually built against.

## Decision

**1. ADR 0002's decision 1 stands. The deployable unit is still one image, one `KERN_VERSION`.**

This ADR does not reopen per-module install, per-instance module versions, or runtime module
loading — the reasons ADR 0002 gave (module clients compiled into the app bundle, `kernel.call()`
checked at compile time, one Postgres and one migration history, an untestable version matrix) are
still true and still block it. The marketplace is what would reopen that, and it still needs a
runtime-loading boundary that does not exist.

What changes is upstream of the image: how the kernel version and each module's version arrive at the
combination that goes into a build, and how fast a safe combination gets there.

**2. `@kernhq/kernel` and `@kernhq/contracts` are `peerDependencies` of every module, not
`dependencies`.**

A module already declares the range of kernel it was built against — that declaration existed, it was
just in the wrong field, so npm never enforced it. As a `peerDependency`, the host (`core`, `chat`,
`mail`) must supply a kernel version the module actually accepts; installing one it does not is now a
resolution failure, not a silent substitution. The range still lives in `devDependencies` too, so the
module's own standalone build and test suite keep a copy to build against.

**3. A host service runs `strict-peer-dependencies=true` and forces one resolved kernel copy.**

`auto-install-peers` alone downgrades an unmet peer to a warning; `strict-peer-dependencies=true`
(set in `core`, `chat`, `mail`'s own `.npmrc`, since each is built standalone) makes it fail
`pnpm install` instead. `pnpm.overrides` still forces every module in the same process onto one
resolved `@kernhq/kernel` — the fix for the two-kernel-instances bug — but an override is a resolution
choice, not an exemption from the peer check: if the forced version does not satisfy a module's
declared range, install still fails. Both properties are needed together: the override gives one
instance; the peer declaration is what notices when that one instance is wrong for what it is running.

**4. Kernel and module versions bump on their own schedule; only the combination is gated.**

`renovate.json` already automerges `@kernhq/*` bumps in `core`, `chat` and `mail` on green CI. That
was already true before this ADR — what was missing was something for it to check. With kernel moved
to a peer dependency, the same automerge now means: a module that publishes a version compatible with
the kernel already pinned goes out the same day, without waiting on unrelated kernel work; a module
that needs a kernel that has not shipped yet fails install, stays red, and does not merge — until the
kernel bump lands (on its own schedule, gated the same way by whatever depends on it), at which point
the same Renovate PR is retried and merges on its own. Nobody hand-coordinates the order; the order is
whatever sequence of independent, individually-safe merges happens to produce a working combination.

The nightly release (`release.yml`) is unchanged: it still cuts one `KERN_VERSION` from whatever
landed on `main` since the last one. What lands on `main` now keeps pace with each part's own
readiness instead of a person remembering to bump a pin.

## Addendum (2026-09-02): the nightly release performs the reach, because nothing else did

Decision 4 relied on Renovate. Renovate was installed on the organisation and opened no pull request
and no dependency dashboard in any repository — not once. So the mechanism this ADR described never
ran, and the consequence was measured rather than imagined: every image from 0.1.0 to 0.1.4 carried
`tracker 0.11.8`, `quire 0.10.9` and `hr 0.16.0` while npm held 0.11.14, 0.16.0 and 0.20.3. Two
things kept them there: a caret on a 0.x range never crosses a minor, and the services commit no
lockfile, so Docker's dependency layer — keyed on `package.json` — was served from cache since the
last time a range was edited by hand. Five releases changed no module and said they did.

What replaces decision 4:

1. **`release.yml` advances the services itself** (`scripts/reach.mjs`). Before tagging, it takes
   the framework at its newest stable version and each module at the newest version whose peer
   ranges accept that framework — one version per module across every service, because a module's
   server runs in `core` and its client in `shell`. It commits the ranges **with a lockfile** on a
   `release/reach` branch, waits for each repository's own CI, and lands all of them on `main` or
   none. A module that has not caught up with the framework is held at its current version, named
   in the release notes, and the run ends red: the fix is to republish the module, never to move
   the host down.
2. **The services commit `pnpm-lock.yaml`** from the first reach onwards. What an image contains
   is then a committed fact, and a moved lockfile is a rebuilt layer. Editing a range in a service
   by hand now means `scripts/relock.sh <service>` in the same commit, which `check-ranges.mjs`
   already enforces.
3. **A module's version moves the platform's.** A module that moved a minor between two releases
   makes the release a minor; the release notes carry each module's changelog entries between the
   version the previous release shipped and the one this release ships.

Decisions 1–3 are unchanged. Renovate stays installed for the non-`@kernhq` dependencies it may one
day open a pull request for; nothing in the release depends on it.

## Consequences

- A module author (first-party or not) who widens what their module needs from the kernel must widen
  the module's own declared range — that is the whole mechanism, not an extra step.
- `check-ranges.mjs` (does a declared range reach what is published) and this peer check (does what is
  installed satisfy what is declared) are different questions; both still run.
- A host service's `.npmrc` gaining `strict-peer-dependencies=true` can surface *pre-existing* peer
  mismatches unrelated to `@kernhq/*` (`better-auth`'s own drizzle-orm peer range, in `core`, at the
  time of writing) as install warnings. These are `auto-install-peers`-resolved already and not new
  failures; they were already there, just unexamined.
- `minKernel` (ADR 0002, checked against `KERN_VERSION` at boot) is unchanged and still exists for the
  case it was built for: a custom build where the image and the module package move independently of
  this repository's own pipeline entirely, and where a `package.json` range was never in the loop to
  begin with.
