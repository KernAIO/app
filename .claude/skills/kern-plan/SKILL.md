---
name: kern-plan
description: Decide what Kern builds next and in what order, on your own judgement — survey what actually exists before trusting any plan document, apply the project's standing priorities, cut the work into slices that ship end to end, and record the decision where the next person will find it. Trigger when asked what to work on, when a work session starts with no specific task, before proposing a roadmap change, or when a request is bigger than one change.
---

# Deciding what Kern does next

Kern is built by one person and a series of agents who each arrive with no memory. Planning is
therefore not a ceremony — it is how a session that starts with "carry on" produces the right thing
instead of the nearest thing.

You are expected to make this call yourself and defend it in a paragraph. Ask the owner only when two
readings of the goal lead to materially different work.

## 1. Survey reality before reading any plan

Plan documents describe intent. They go stale the moment something ships. Start from the ground:

```bash
pnpm status                                             # every checkout: dirty, unpushed, stashed, missing
for r in app core chat mail collab kernel modules docs; do
  printf '%-8s ' "$r"; gh run list -R "KernAIO/$r" --limit 1 --json conclusion,workflowName \
    --jq '.[] | "\(.workflowName): \(.conclusion)"'
done
gh issue list --repo KernAIO/app --limit 30
ls repos/modules/packages                               # which modules exist at all
grep -n "registerModule" repos/shell/src/lib/modules/registry.ts   # which are reachable in the UI
```

The gap between "a package exists" and "it is registered in the app" is where this project's unfinished
work hides. A module in `packages/` that no service imports and no registry registers is a directory,
not a feature.

Then read `ROADMAP.md` for the target, `docs/PLAN.md` §3 for the v1.0 checklist, and `docs/adr/` for
decisions you must not silently reverse. `KERN-PLAN.md` at the desktop root is the origin record —
read it, do not rewrite it.

## 2. Standing priorities

These come from the project's own stated goals; apply them in order.

1. **Red before new.** Failing CI, a broken self-host compose, a migration that does not apply — these
   outrank every feature. Nothing is worth building on top of a red build.
2. **Finish what is half-wired.** A module with a server and no client, a screen that lists rows it
   cannot act on, a contract with unimplemented procedures — each is a debt that grows. Kern is not
   an MVP: "listed but not editable" is not a feature that shipped.
3. **Unblock the dependency graph.** `kernel`/`contracts` → `modules` → services → `app`. Work that
   unblocks three other pieces beats work that is merely next on a list.
4. **Vertical slices, not layers.** Ship one capability all the way through — contract, server, RLS,
   client, navigation, i18n — before starting the next. A backend-only sprint produces nothing a user
   can see and hides its own bugs until much later.
5. **Then breadth toward v1.0.** The roadmap is wide (tracker, chat, docs, HR, recruiting, CRM,
   automation, mail, calls, AI). Pick the area that unlocks the most of the rest — the platform
   primitives (permissions, search, files, notifications) usually do.
6. **Self-host works, publicly.** Every repo is public and every commit is read by strangers. Work that
   makes the thing installable and legible counts as product work, not chores.

## 3. Cut it into slices that ship

A slice is a sentence a user would recognise: "a member can be given a custom role and immediately
loses access to what the role forbids". Not "add the roles table".

For each slice, name up front:
- the contract change (and therefore the publish order — see `kern-release`),
- which module or service owns it (see `kern-module` before assuming a new one),
- the screens that make it reachable (see `kern-ui`),
- what you will run to prove it works, not what will type-check.

Three to six slices is a plan. Twenty is a wish list — the roadmap already holds those.

## 4. Record the decision where it will be found

- **A choice with consequences** (a dependency, a protocol, a boundary between services) → an ADR in
  `docs/adr/`, numbered, with Context / Decision / Consequences, in the same commit as the code.
- **A change in what v1.0 contains or when** → `ROADMAP.md`.
- **Work to be picked up later** → a GitHub issue, written for an outside contributor:
  ```bash
  gh issue create --repo KernAIO/<repo> --title "…" --body "…"
  ```
- **Something the next agent would otherwise re-derive** → `CLAUDE.md`, via the `kern-improve` skill.

Do not leave the plan only in the chat. The chat is gone next session; the repo is not.

## 5. Present it honestly

When you propose the plan, say in a few lines: what you picked, what you rejected and why, what it
depends on, and what you are unsure about. If the survey turned up something the owner probably does
not know — a module half-wired, a workflow failing for a week, a roadmap item already obsolete — lead
with that. Discovering it and not saying it is the worst outcome of a planning pass.
