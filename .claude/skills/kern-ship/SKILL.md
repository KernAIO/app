---
name: kern-ship
description: Standing authority to commit, branch, push, version and release without asking. Covers what you decide alone (branch, message, semver bump, changeset, when to commit, when to tag), the bar a release has to clear before you cut it, what you never do unasked (publish a half-finished feature, force-push, rewrite history), and how to report what shipped instead of asking for it. Trigger at the start of any work in a Kern repository, and immediately whenever you are about to ask "should I commit this?", "which branch?", "shall I push?", "what version bump?" or "do you want me to release this?".
---

# Shipping without asking

Navid does not manage the git or release mechanics of this project. You do. The rule is one
sentence: **you are the engineer — everything from the first commit to the tag is yours.**

Asking "shall I commit this?" or "shall I release this?" is not caution here, it is work handed back.
He answered both questions once, in this skill, for every future session (2026-08-25). What replaces
the question is the bar below: nothing gets tagged that is not finished and green, and the absence of
an approver is exactly why that bar is not negotiable.

## You decide these, alone, every time

| Decision | What you do |
|---|---|
| Whether to commit | Commit. At every coherent step, not once at the end. |
| Which branch | `main`, unless the change is genuinely experimental or you were told otherwise. This org pushes to `main`. |
| Commit message | Conventional Commits, imperative, ≤72-char subject, an honest body when the reason is not obvious. No AI trailer, no `Co-Authored-By: Claude`, no `Claude-Session:`. |
| Whether to push | Push, straight after the commit. `git -c rebase.autoStash=true pull --rebase` first — parallel agents share these worktrees. |
| Semver bump | Yours. Contract or behaviour a consumer depends on changes → minor while pre-1.0, major after. Bug fix that keeps the surface → patch. |
| The changeset | Write it in the same commit as the change, in the publishing repo. One honest sentence about the effect, not the diff. |
| Fixing your own CI failure | Fix it and push again. A red run you caused is not a decision, it is the rest of the task. |
| Cutting the release | Yours, once the work clears the finished bar below. Tag it, let `release.yml` run, then report what shipped. |

Do not narrate any of this while it happens. Report it at the end, in one line per repository:
what landed, where, what version it will publish as.

## You never do these without being asked

- **Publish an unfinished feature.** Below. This is the real constraint on releasing: a tag says
  instances on `auto` may apply it unattended at 03:00, so the question is never "am I allowed",
  it is "is this true".
- **Force-push, rewrite history, delete a branch or a repo, or change org settings.** These are not
  yours in any mode.
- **Commit a secret, a token, or a machine-specific path.** Every repo is public the moment you push.
  `.env` is gitignored; `.env.example` is the interface.

## An unfinished feature still gets committed — it does not get released

Half-built work belongs on `main`, committed and pushed, the same day it is written. Nothing is
served by holding it hostage in a dirty worktree that the next session inherits.

What it does not get is a version. Concretely:

- **No changeset** while the feature is incomplete, so `changeset publish` cannot pick it up. Land the
  commits; add the changeset in the commit that finishes the work.
- **No tag**, and no suggestion of one.
- If the incomplete surface is reachable — a route, a procedure, a menu item — it does not ship
  reachable. Leave it behind the module registration, a flag, or simply unregistered, and say so in
  the commit body. A user finding a dead screen costs more trust than a week of delay.

The exception that proves it: a *complete* small change inside a larger unfinished feature (a schema
migration, a contract addition, a fixed bug) is finished work and gets its changeset now. "Unfinished"
means the thing a user would name, not the branch.

## When it is actually finished, release it

Finished is not "the code compiles". Before you are allowed to tag, the relevant bar has been met and
you have run it, not just typed it:

- `pnpm typecheck && pnpm lint && pnpm test && pnpm build` pass.
- Backend work meets `kern-service` — every procedure implemented and authorised, tenant isolation,
  events emitted, migrations idempotent and backward-compatible.
- UI meets `kern-ui` — reachable, permission-gated, loading/empty/error states, i18n, RTL, dark mode.
- `pnpm status` is clean: ten repositories, ten answers, and `website` sits beside the umbrella where
  a `repos/*` loop misses it.

Then cut it. Follow `kern-release` for the rollout order, the feed fields and the checks — the
authority to tag is not a licence to skip any of it — and watch the chain through: `release.yml`
tags the service repos, waits for the images, publishes the umbrella release; `release-feed.yml`
signs the feed; `rollout.yml` pins `KERN_VERSION` and waits for `/api/health` to report it. A tag
that stalls half way is yours to finish, not something to report as done.

Then report, in one short message, after the fact:

> `tracker` is finished and shipped — recurring issues, the widget, and the KQL date filters.
> `@kernhq/module-tracker` published as 0.4.0 and it went out as Kern v0.3.0;
> `app.kernaio.com` is reporting 0.3.0 on `/api/health`.

What that message contains: what is done, the versions it carries, and where it is live. What it must
not contain: a request for permission, a question about branches, or a list of the commits you made.
Those were all yours.

If something is *not* ready — a suite you could not run, a bar you could not meet — do not tag it and
do not dress the gap up as a question about releasing. Say plainly what is unfinished and what would
finish it. That is a status report, not a request for approval.

## Two failure modes this skill exists to prevent

**Asking.** Every "shall I commit?" is a session that stops and waits for a person who already said
yes. If you catch yourself composing that sentence, delete it and run the command.

**Shipping to be helpful.** The other direction is worse and rarer: a tag cut because the work felt
done. An instance on `auto` will install it while nobody is watching, and now nobody signs it off but
you. When you are unsure whether something is finished, it is not — commit it, push it, and say what
remains.

This file is one of them. It lives in the `kern` repo, so writing it was a commit, and you made it
without asking.
