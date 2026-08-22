---
name: kern-improve
description: Turn what a work session learned into something the next session inherits — deciding between a CLAUDE.md line, a new or edited skill, an ADR or a docs page, writing it in the house voice, and auditing the existing skills and notes for anything that stopped being true. Trigger after finishing a piece of work, after debugging something that cost real time, when a rule was repeated twice, or when asked to improve the project's own tooling.
---

# Improving how Kern gets built

Every agent that works on Kern starts from nothing but this repository. Whatever a session worked out
and did not write down, the next one pays for again. This skill is the write-down step, and it is part
of the work — not an optional epilogue.

## 1. What is worth keeping

Ask of anything you learned: **would the next agent get this wrong without being told?**

Keep:
- a trap — a silent failure, a misleading error, a tool that reported success and did nothing
  (`localhost` resolving to `::1` in CI; `changeset publish` skipping a private package),
- a convention you had to infer by reading four files,
- a decision whose obvious alternative is wrong, with the reason,
- a completeness bar — the things people keep forgetting to do for a *kind* of work.

Do not keep: what the code already says, what `git log` already says, anything true only of the change
you just made, or a summary of what you did. A note that restates the diff is noise that makes the
real notes harder to find.

## 2. Where it goes

| What you learned | Where | Timing |
|---|---|---|
| A repo-specific trap, port, env contract | that repo's `CLAUDE.md` | same commit as the change |
| A rule for every repo (git, layout, quality bar) | umbrella `kern/CLAUDE.md` | same commit |
| A decision with architectural consequences | `docs/adr/NNNN-*.md` | same commit |
| Something a *user* or self-hoster needs | `docs/`, `README.md`, `selfhost/` | same commit |
| A repeatable procedure or completeness bar | a skill in `kern/.claude/skills/` | when it recurs |

"Same commit as the change that taught you" is the rule that makes this survive. A separate
documentation commit gets postponed until it is forgotten or wrong.

## 3. When to write a skill instead of a line

A skill earns its place when the knowledge is a **procedure or a bar applied repeatedly**, not a
single fact. `kern-service` and `kern-ui` exist because "is this done?" has a long, forgettable answer.

Before creating one, check whether an existing skill should grow instead — five overlapping skills are
worse than three sharp ones, because the wrong one gets loaded.

Anatomy of one that works here:

```
kern/.claude/skills/<name>/SKILL.md
---
name: <name>
description: <what it covers, then the trigger — "Trigger when …">
---
```

- The description is the only thing read when deciding to load it. Write the trigger explicitly.
- One page. If it needs more, split the detail into `references/` and keep the entry short.
- Real commands from this project, runnable as written.
- Real failures from this project, named. "The mail module shipped with no `defineServerModule` at
  all" teaches more than a paragraph of principle.
- Imperative and specific. No throat-clearing, no "it is important to".

Then symlink it so the desktop working directory sees it too, the way the others are:

```bash
ln -s /Users/navid/Desktop/Kern/kern/.claude/skills/<name> /Users/navid/Desktop/Kern/.claude/skills/<name>
```

## 4. Audit what is already written

A stale note is worse than none, because it is trusted. Periodically — and always when you touch an
area a note describes:

```bash
# do the paths and scripts the notes cite still exist?
grep -ohE '(repos|packages|scripts|selfhost)/[A-Za-z0-9_./-]+' \
  CLAUDE.md .claude/skills/*/SKILL.md | sort -u | while read -r p; do
  [ -e "$p" ] || echo "MISSING: $p"
done
# do the commands still run?
grep -hoE 'pnpm [a-z:]+' CLAUDE.md .claude/skills/*/SKILL.md | sort -u
```

Paths written relative to a repo (`packages/tracker`) show up as missing from the umbrella root —
check before deleting. Everything else is real: this exact sweep found `kern-ui` citing a
`tokens.css` that had moved under `src/lib/`, which would have sent someone hunting for tokens that
were never there.

Then delete what stopped being true, in the same pass. Deleting a wrong line is a contribution.

## 5. Improve the machinery, not only the notes

Friction that repeats is a bug in the workspace:

- A command everyone runs by hand → a script in `scripts/` and a line in `package.json`.
- A mistake CI cannot catch → a check that can (`check:pack` exists because a broken tarball passed
  every test).
- A permission prompt hit constantly → `.claude/settings.json` (the `fewer-permission-prompts` skill).
- A step forgotten every time → add it to the relevant skill's checklist, not to your own memory.

## 6. Close the loop out loud

When you finish, say plainly what you wrote down and where — one or two lines. If you learned
something and decided **not** to record it, say that too and why. The point is that the next session
starts further along than this one did; silence about it is how a project quietly stops compounding.
