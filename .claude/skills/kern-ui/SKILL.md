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
- Add keys to **all** locale files under `repos/app/messages/`. Write English and Persian properly; if
  you cannot write Arabic or German, say so in your report rather than leaving them silently English.
- Layout uses logical properties (`ms-`, `me-`, `start`, `end`). Never `left`/`right`. Verify with
  `dir="rtl"`.
- Verify light **and** dark. A colour that reads in one may vanish in the other — `--kern-ink-900`
  inverts, so a checked switch using it became white-on-white in dark mode.

## 7. Design fidelity

`repos/app/DESIGN.md` is the authority: exact tokens, sizes, and per-view anatomy. Use tokens that
exist (`repos/kernel/packages/ui/src/lib/styles/tokens.css`) — an invented name resolves to nothing and fails
silently. Check a component's real props before using it; several differ from the obvious guess.

## 8. Accessibility

Every control has an accessible name (`ariaLabel` on a checkbox with no visible label). Dialogs trap
focus and close on Escape. The active nav item carries `aria-current`. Icon-only buttons carry a label.

## 9. Verify by running it

Type-checking is not verification. Run `pnpm dev:mock`, open the screen, exercise each action, and
look at it in both themes — with screenshots if Chrome tooling is available. Then run
`pnpm lint && pnpm typecheck && pnpm build && pnpm test`.

State plainly in your report what you exercised and what you did not.
