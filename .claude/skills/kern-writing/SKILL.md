---
name: kern-writing
description: Kern's house style for anything a person reads — READMEs, the docs site, self-host and upgrade guides, runbooks, ADRs, release notes and error text. Covers where each kind of document belongs, goal-first structure, one action per step, conditions before commands, an observable result after every important action, measured numbers, and the rule against documenting what does not exist. Trigger before writing or revising any Markdown someone outside this session will read.
---

# Writing for a reader who is not you

Kern's readers are a self-hoster pasting a command into a server at midnight, a contributor who
found the repository an hour ago, a workspace admin who is not an engineer, and the next agent, who
arrives with no memory at all. None of them has your context, and none of them will ask you a
question — they will guess, or leave.

Every repository is public, so the documentation is part of what people judge Kern by, in the same
way the code is. It is also the only part of the project with no compiler: nothing here fails a
build when it goes stale, so the discipline has to be yours.

## 1. Decide where it goes before you write a word

| What you are writing | Where it lives | Read first |
|---|---|---|
| How to install, operate, upgrade or use Kern | a page in `repos/docs`, in the sidebar | this skill |
| What one repository is, and how to run it alone | that repo's `README.md` | this skill, `kern-repo` |
| Why we chose this and what we rejected | `kern/docs/adr/NNNN-<slug>.md` | §10 |
| A trap that will cost the next agent an hour | that repo's `CLAUDE.md`, same commit | `kern-improve` |
| How Kern itself gets built | a skill under `.claude/skills/` | `kern-improve` |
| What a release changed | the changeset, then the release feed | `kern-release` |
| A string a user sees in the product | `repos/shell/messages/*.json` | `kern-language` |
| Marketing copy, pricing, the landing page | `website` | — |

The common mistake is an operator guide inside a README. A README answers "what is this and how do
I run it"; anything a person *follows* — install, upgrade, back up, configure — belongs on the docs
site, where it has a sidebar, a search index and an edit link. The second mistake is reference
material inside an ADR: an ADR records a decision at a date, and stops being edited.

## 2. Goal, then requirements, then steps — in that order

Open with one sentence naming what the reader will have when they finish. Then everything they need
before starting: versions, ports, credentials, a domain, disk. Then the steps.

A reader who cannot tell from the first screen whether this page is for them will read the whole
page to find out. `self-hosting/install.md` is the model: what the machine needs, what the software
needs, how much memory it uses, then the one-line install.

Never put background between two required actions. Rationale, alternatives and history go after the
procedure, or under their own heading. A reader must be able to follow only the numbered steps and
arrive at a working result.

## 3. One action per step, and the condition before the command

```markdown
<!-- no -->
Open Settings, choose Modules, enable HR and save.
Run `pnpm i18n` if the key is new.

<!-- yes -->
1. Open **Settings → Modules**.
2. Switch **HR** on.
3. Select **Save**.

If the key is new, run `pnpm i18n`.
```

A step that hides a second action behind a comma is the step people half-do. A condition written
after its command is a condition people meet after acting on it.

Headings are literal and searchable, because that is how they are used: `Upgrading`, `If Caddy will
not issue a certificate`, `Environment reference`. Not `Some notes on TLS`.

## 4. Every important action ends in something the reader can see

State the observable result — exact output, a file that now exists, a screen that changed — and
what to do next when it appears.

> 4. Check that every service came up:
>
>     ```bash
>     docker compose ps
>     ```
>
>     Every service reads `running`, and `caddy` holds ports 80 and 443.
>     If `core` restarts in a loop, go to **If core will not start**.

Without this, the reader's only test of success is whether an error appeared, and a silent partial
failure reads as a success. Recovery sections follow the same order every time: the exact symptom
first, then the cause, then numbered actions.

## 5. Write so a reader can be interrupted

Assume every reader stops mid-procedure and comes back to a page they no longer remember.

- Repeat the noun. "Paste the value you copied earlier" becomes "Paste the **instance admin token**
  into `KERN_ADMIN_TOKEN`".
- Name the steps. "Repeat the procedure above for the other services" becomes "Repeat steps 2–4 for
  `chat`, `mail` and `collab`".
- Never make a step depend on something visible only on a different page.
- In a long procedure, say where the reader is: `Step 3 of 7`. A stale counter is worse than none —
  if you add a step, fix the counters in the same edit.

## 6. The sentence shape

These are Kern's limits, not a standard's, and meaning wins over any of them:

- Procedural sentences: aim for 8–15 words, never past 20. One instruction each.
- Descriptive sentences: never past 25 words.
- Paragraphs: one topic, two to four sentences. Anything list-shaped becomes a list.
- Lists: one level of nesting in a procedure.
- One name per thing, everywhere. A module is `HR` in the sidebar, `HR` in the docs and `hr` in the
  schema — say which you mean and never invent a third.
- Split long sentences; do not delete the step that made them long.

The docs site is English only — no locales are configured in `repos/docs/astro.config.mjs`, while
the product itself speaks four languages. Most readers of an English page are reading their second
language. Idiom, humour that depends on register, and clever headings all cost them; plain wording
costs no one.

## 7. Say the number, and have measured it

Kern's docs quote real figures — container memory at rest, image size, how many people a 4 GB box
suits. Those came from running the containers, and `CLAUDE.md` requires them to be re-measured
rather than nudged. The same holds for anything you write: if you cannot say where a number came
from, either measure it or leave it out. A number nobody measured is the one a self-hoster sizes a
server on.

Do not hardcode a version where the reader could read the current one. Everything in an instance
carries the same `KERN_VERSION`, and a doc pinned to a version somebody bumped last month is wrong
without ever being edited.

## 8. Say why, once

Kern's voice explains its reasoning, briefly, in the place the reader is deciding something —
"so the 4 GB is not for idling; it is the room Postgres uses to cache your data". One or two
sentences, after the instruction, never instead of it. A reader who understands why the setting
exists chooses correctly when their situation is not the one you wrote for.

Do not extend this into an essay. Long reasoning is what an ADR is for; link to it.

## 9. Never document what does not exist

The README's rule is the project's rule: *what actually runs, not what is planned*. Mark the state
of anything unfinished, on the page itself, in the first screen.

This is Kern's live failure, not a hypothetical one: `repos/docs/src/content/docs/modules/hr.md` and
`crm.md` describe employees, org charts, leave approvals, pipelines and web-to-lead forms in the
present tense, while the README lists HR and CRM as **Not built**. A reader who trusts the docs site
installs Kern to get a feature that has no code. If you write a page ahead of the build, open it
with a plain line — `Planned. Not in a release yet.` — and delete that line in the commit that ships
the feature.

The same applies to a step you did not run. Do not write a procedure from reading the source; run
it, and write what happened.

## 10. The mechanics that bite

**A docs page.** Frontmatter carries `title` and `description` — the description is the search and
social snippet, so write it as a sentence about the page, not a keyword list. A page is only
reachable if `astro.config.mjs` lists it in the sidebar; adding the file is half the change. Then:

```bash
cd repos/docs
pnpm exec biome check --write src/content/docs/<path>.md
pnpm typecheck      # astro check
pnpm build          # the sidebar and every referenced slug resolve here, or not at all
```

**An ADR.** `docs/adr/NNNN-<kebab-slug>.md`, numbered in sequence, opening with `# ADR NNNN — <the
decision>` and a `- Status: accepted (YYYY-MM-DD)` line. State the problem precisely, list the
options you rejected and why they are worse, then the decision in numbered parts, then the
consequences you accept. Read `0007-module-capabilities.md` before writing one. An ADR is a record:
supersede it with a new one rather than rewriting it.

**A README.** Written for a stranger. What this is, what state it is in, how to run it alone, how it
fits the whole, where the docs are. Not our notes to ourselves — those are `CLAUDE.md`.

## 11. What this does not govern

Code comments and commit messages keep the voice they have; see `kern-ship` for commits. User-facing
strings in the app go through Paraglide and belong to `kern-language` — including error text a user
reads on screen. Error *messages a developer reads*, and what an API is allowed to say, belong to
`kern-service`.

This skill governs how a document is *built*. What it is allowed to *claim* — the voice, the words
Kern never uses, the positioning and boilerplate, the spelling of every name — is
`KernAIO/brand`'s [`docs/voice.md`](https://github.com/KernAIO/brand/blob/main/docs/voice.md),
checked out at `../brand` beside this workspace. Read it before writing anything persuasive: a
landing page, a release note, a README's opening, an error a user reads.

## 12. Before you call it written

- The goal is in the first sentence, and the requirements are complete enough to decide to start.
- Every required action is its own step, with no second action after a comma.
- Every condition sits before the command it governs.
- Every important action states an observable result.
- A reader returning after an interruption can resume from any step without re-reading.
- Optional material, rationale and alternatives are outside the required path.
- Every number was measured, every command was run, every path exists.
- Nothing unbuilt is described in the present tense.
- The page is in the sidebar, `pnpm typecheck` and `pnpm build` pass in `repos/docs`, and Biome has
  formatted the file.
- Read it once as the reader — a person at a terminal at midnight, not the person who wrote it.
