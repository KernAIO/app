---
name: kern-ui
description: The completeness bar for any Kern screen — use before calling a page, view, dialog or component "done". Covers reachable capabilities, row actions, permission gating, loading/empty/error states, destructive confirmations, i18n, RTL, dark mode and design fidelity. Trigger whenever building or reviewing UI in the app or a module client.
---

# Kern UI completeness

Kern is not an MVP. A screen that lists data but cannot act on it is unfinished, even if it looks
right. Work through this before saying a screen is done.

## 1. Every capability must be reachable

The most common failure is a screen that renders data and quietly drops half the API.

**Audit it mechanically, not by memory:**

```bash
# what the API offers for this entity
grep -n "members:\|invitations:" -A 14 repos/kernel/packages/contracts/src/core/router.ts

# what the screen actually calls
grep -oE "api\.[a-zA-Z.]+\.[a-zA-Z]+" "path/to/+page.svelte" | sort -u
```

Account for **every** procedure: it is either reachable from the UI, deliberately out of scope for this
screen (say where it lives instead), or not built yet (say so in your report — never silently).

A real example from this project: the members page shipped listing members while `members.update`,
`members.remove` and `members.leave` all existed. You could not change a role or remove anyone.

## 2. Rows need actions

A table row representing something editable needs a way to edit it. Prefer an end-aligned overflow
menu (`DropdownMenu`) over a row of buttons; keep destructive items last and marked `danger`.

Ask per row: change its important attributes? remove it? open its detail? copy its identifier?

## 3. Gate on permission, and say why

Every action checks `session.can('…')`. Hide what the user may never do; disable — **with a tooltip or
hint explaining why** — what they cannot do *right now* (the last owner cannot be demoted; a module
other modules depend on cannot be switched off). A disabled control with no explanation is a bug.

## 4. Four states, always

- **Loading** — `Skeleton` shaped like the content, never a bare spinner in a content area
- **Empty** — `EmptyState` with a sentence and, where possible, the action that fills it
- **Error** — a message and a way to retry; never a silent blank
- **Busy** — the control that triggered the work shows `loading`, and cannot be triggered twice

## 5. Destructive actions

Confirm in a `Dialog` that states **what happens and to whom** — "everyone in this workspace loses
access… nothing is deleted" beats "Are you sure?". Never use `window.confirm`. If the action is
reversible, offer **Undo** in the success toast instead of a confirmation. If the control flips
optimistically (a switch), it must snap back when the user cancels.

## 6. Language, direction, theme

- Every user-facing string goes through Paraglide. No hardcoded English — including toasts, aria
  labels, tooltips, placeholders and confirmation copy.
- Add keys to **all** locale files under `repos/shell/messages/`. Write English and Persian properly; if
  you cannot write Arabic or German, say so in your report rather than leaving them silently English.
- Layout uses logical properties (`ms-`, `me-`, `start`, `end`). Never `left`/`right`. Verify with
  `dir="rtl"`.
- Verify light **and** dark. A colour that reads in one may vanish in the other — `--kern-ink-900`
  inverts, so a checked switch using it became white-on-white in dark mode.

## 7. Design fidelity

`repos/shell/DESIGN.md` is the authority: exact tokens, sizes, and per-view anatomy. Use tokens that
exist (`repos/kernel/packages/ui/src/lib/styles/tokens.css`) — an invented name resolves to nothing and fails
silently. Check a component's real props before using it; several differ from the obvious guess.

**A wrong token name is invisible, so check it mechanically.** `var(--kern-radius-sm)` does not
exist; the token is `--kern-r-sm`. Thirty uses of it had shipped across seventeen tracker files, and
every one of those corners rendered square in an interface where nothing else is. Nothing failed —
not the build, not the types, not the tests. After touching CSS, run:

```bash
# every token a file references, minus every token that is defined — the difference is your bugs
comm -23 \
  <(grep -rhoE 'var\(--kern-[a-z0-9-]+' repos/shell/src repos/kernel/packages/ui/src | sed 's/var(//' | sort -u) \
  <(grep -hoE '^\s+--kern-[a-z0-9-]+' repos/kernel/packages/ui/src/lib/styles/*.css | tr -d ' ' | sed 's/:$//' | sort -u)
```

A fallback (`var(--kern-radius-md, 12px)`) hides the same mistake behind a value that looks
deliberate. Prefer no fallback, so a wrong name shows up as a missing style instead of a lie —
`--kern-gutter`, `--kern-shadow-menu` and `--kern-ink` all hid this way, and `--kern-ink` had no
fallback at all, so three hover states simply never changed colour.

The command also lists custom properties a component defines on itself (`--kern-lane-dir` in
`BoardView`). Those are fine — check each hit before changing it.

## 8. Accessibility

Every control has an accessible name (`ariaLabel` on a checkbox with no visible label). Dialogs trap
focus and close on Escape. The active nav item carries `aria-current`. Icon-only buttons carry a label.

## 9. Affordance and geometry

Small things that read as sloppiness, in the order they were found in review.

**Anything clickable shows a pointer.** `tokens.css` already sets `button { cursor: pointer }`, so
the only way to get this wrong is to override it — the window tab strip carried `cursor: default`
on the tab, its close button and the `+`, and the whole strip felt inert. Only a genuinely
non-interactive row keeps the arrow (`Table`'s `.ktr` does, and `.ktr.clickable` opts back in).
Sweep the running page:

```js
[...document.querySelectorAll('button:not(:disabled), [role=button], a[href]')]
  .filter(e => e.offsetParent && getComputedStyle(e).cursor === 'default')
```

**Cards in a grid of choices are all one size.** A grid stretches the *cell*, not the button inside
it, so one two-line description makes the card beside it visibly short. Give the grid
`grid-auto-rows: 1fr` and let the cell stretch its child (`> li { display: grid }`).

**A badge that overhangs its button needs room in the ancestor that clips.** A clip box is the
padding box, so `overflow: hidden` on a list slices any badge positioned outside its item — most
visibly in RTL, where `inset-inline-end` is the left edge. Pad the clipping ancestor by the
overhang and cancel it with an equal negative margin: the margin box is unchanged, so nothing
moves, and the badge survives. Check both directions, never just the one on your screen.

## 10. Rich text is a component, not a textarea

Anywhere a user writes prose that is stored as a document — descriptions, comments, documents —
use `RichTextEditor` from `@kernhq/ui/editor`. Never a bare `<textarea>` with a text-to-document
converter: it silently forbids everything the renderer can draw.

Two rules keep it honest:

- **The editor's schema is the renderer's schema.** Configure StarterKit down to exactly the nodes
  and marks the read side draws. A node the editor can produce and the renderer cannot draw
  vanishes on save, and nobody notices until a user complains.
- **The writing surface wears `.kern-prose`, the same class the read view wears.** Nothing moves
  when you press Save, and there is one stylesheet, not two that drift.

Beyond that, the things that separate this from a cheap editor, all of which have to be checked by
using it:

- Toolbar controls cancel `mousedown`; they do not handle `click`. A `contenteditable` loses its
  selection the moment focus moves, so a `click` toolbar bolds a collapsed cursor.
- A link is edited in an inline field with Apply and Remove, never `window.prompt`.
- The `@` menu flips above the caret when there is no room below — a composer sits at the bottom of
  a panel, which is exactly where "always below" falls off-screen.
- A mention is a node with the user's id, not the characters `@Ada`.
- **Snapshot the document before it leaves the component.** It is a Svelte state proxy, and a proxy
  cannot be `structuredClone`d — which is what the API layer does. Pass `$state.snapshot(doc)`, or
  the save throws "could not be cloned" and drops the edit.
- Never read `editor.can().…` from a template expression. `can()` runs a dry-run transaction, which
  fires `onTransaction`; if that bumps reactive state, Svelte throws `state_unsafe_mutation`.

## 11. A dashboard widget has its own bar

A card on the workspace home is judged beside every other module's. Read the `kern-widget` skill
before adding one — what it must not claim, why one configurable widget beats six fixed ones, and
why the keyboard route is the specification rather than the afterthought.

## 12. The machine checks half of this — run it

`repos/shell/tests/e2e/ux.spec.ts` sweeps **every route in four renderings** (light/dark ×
LTR/RTL) against the rules in `ux-audit.ts`, and CI runs it:

| rule | what fails |
| --- | --- |
| `contrast` | text under 4.5:1 (3:1 when large) against the colour actually behind it |
| `name` | an interactive element a screen reader would announce with no name |
| `target` | a control under 24×24 **and** within 24px of another — WCAG 2.5.8, spacing exception included |
| `cursor` | a click target showing the arrow instead of the pointer |
| `heading` | a page with no level-1 heading |
| `overflow` | a document that scrolls sideways |
| `focus` | a control the keyboard reaches with no visible ring |
| — | anything the page throws while rendering |

```bash
cd repos/shell && pnpm test:e2e -- ux.spec.ts     # needs a build; the config makes one
```

Three things about it are worth knowing before you argue with a failure.

- **It measures the rendered page, not the source.** It reads the colour composited down through
  every ancestor background, the real hit area (`elementFromPoint`, so a transparent `::after` that
  grows a 15px button to 25px counts), and the ring a `:focus-within` ancestor draws for a child.
- **It implements the standards as written**, including their exceptions — a small target with room
  around it passes, a disabled control is exempt from contrast, an inline link in a sentence is
  exempt from target size. So a failure is a defect, not a strict test to be loosened.
- **A route it does not list is a route nobody checks.** Adding a screen means adding it to `ROUTES`.

Everything it cannot judge — whether the copy is kind, whether the spacing has rhythm, whether the
empty state suggests the right next thing — is still §1–11 above, and still yours.

### The two defects you cannot see by looking

**Contrast is arithmetic.** Compute the ratio against the surface the text sits on *and* the palest
surface it could sit on (`--kern-canvas` in light, `--kern-surface-active` in dark). This is how the
ink scale below 450 was found to run to 2.5:1, how six of nine avatar grounds turned out to carry
white initials at 2.6–4.1:1, and how `.v-danger` was found putting `#fff` on a light red in dark
mode — on the button that deletes a project.

**`opacity` on a row fades its text against the page.** A "muted" or "disabled" row at 0.5 is
unreadable whatever colour token it names, and opacity fades everything by the same proportion
regardless of where it started. Mute with a colour (`--kern-ink-450`), and keep disabled states at
0.7 — exempt from the contrast rule is not the same as unreadable.

## 13. Verify by running it

Type-checking is not verification. Run `pnpm dev:mock`, open the screen, exercise each action, and
look at it in both themes — with screenshots if Chrome tooling is available. Then run
`pnpm lint && pnpm typecheck && pnpm build && pnpm test && pnpm test:e2e`.

State plainly in your report what you exercised and what you did not.

**A screenshot is a review, not a receipt.** Every time you capture a screen — during a drill, a
smoke test, a payment flow, anything — look at it as a designer before you read it as a tester:
spacing between blocks (a button flush against a list is a defect), the card's padding pooling on
one side, text direction under RTL, a badge or a number that overflows, a banner whose words are
untrue for the state it describes. On 2026-09-04 a billing screen was screenshotted three times
while proving Stripe worked and nobody noticed the *Choose* button had no gap above it and the
card's padding sat underneath it; the owner did, from the same picture. What the machine sweep
(`ux.spec.ts`) cannot judge — rhythm, gaps, alignment, copy — is yours to judge in that moment, and
a defect seen and not fixed is a defect shipped. Fix it before moving on, or write it down with the
screenshot's name.
