---
name: kern-widget
description: How a module puts a card on the workspace dashboard — naming the procedure before designing the card, one configurable widget instead of six fixed ones, acting on a row rather than linking away from it, declaring sizes and surviving all of them, and keyboard parity for anything the pointer can do. Trigger when adding a widget to a module, when a module ships a feature somebody would want on their home page, or when reviewing anything under `repos/app/src/lib/dashboard` or a module's `widgets/`.
---

# Putting a module on the dashboard

The dashboard is the first screen anybody sees, and it is the one place where every module is
judged side by side. A widget that shows a number nobody can act on, or a number nothing actually
counts, makes the whole platform look like a demo. Work through this before adding one.

## 1. Name the procedure before you design the card

A widget is a view of data that already exists. Find the procedure first, and if there is not one,
the honest answers are "add it to the module" or "not yet" — never "approximate it".

```bash
# what this module actually offers
grep -nE "^\s+(list|get|query|counts|unread|stats):" -B2 repos/modules/packages/<id>/src/contract/*.ts
```

Three real cases from building this:

- **"Unread mail"** was designed, drawn and then deleted. The mail module is outbound only —
  `deliveries`, `suppressions`, `inbound_routes` — and the personal inbox is deferred to v1.1.
  There was never anything to read.
- **A member count** was cut because `paginate()` returns `{items, nextCursor}` and no total. The
  choices were to lie or to walk every page; the widget became a list instead.
- **Failed sends** shipped as "of the last 50", because `deliveries.list` has no total and no date
  filter. A smaller true statement beats a bigger invented one, and the note says so on the card.

## 2. One configurable widget beats six fixed ones

Before adding `assigned-to-me`, `due-soon`, `in-review` and `created`, check whether the module
already has a procedure that takes a query. The tracker does: `issues.query` takes KQL and is what
every view, board and report runs through, so all four are one widget with a `select`. It is also
what lets somebody place the same card twice showing two different things, which is the difference
between a dashboard and a fixed page.

Settings are **declarative** — `WidgetSettingField` in `@kernhq/kernel/client` — and the shell
generates the form. A widget that draws its own settings dialog looks different from every other
widget, and nothing can make sense of its stored values once it is gone.

**Every setting must be in the query key.**

```ts
queryKey: ['tracker', 'issue', workspaceId, 'widget', settingsScope(settings), kql]
```

Leave it out and TanStack serves the cached answer: changing the project does nothing, only on a
warm cache, which is indistinguishable from the setting being broken. `includeArchived` on the
tracker settings pages shipped this exact bug once already.

## 3. A row does what that row does elsewhere

A widget that only links away is a table of contents. Ask what somebody does with the thing they
just saw, and put it on the row: mark a notification read, apply a transition, stop the timer,
accept out of triage. Reuse the module's own procedures — a widget is not a place for a second
implementation of anything.

Hide row actions while `editing` is true. Somebody rearranging the board is not acting on it, and a
stray click that archives something during a drag is unforgivable.

## 4. Sizes are a contract, and every one has to look right

`sizes` is the closed list of what a person may choose; the resize handle and the menu offer nothing
else. Declare only sizes you have looked at. A cumulative-flow chart is unreadable below full width,
so it declares `['xl']` and the resize handle does not appear.

A single number sets `compact: true` and draws no header — its own label is the name, and a header
above it says the same word twice while eating the height the number needs. The grip and menu float
over the card in edit mode instead, so its geometry never changes between reading and arranging.

## 5. Four states in a three-hundred-pixel box

Use `WidgetState`: a skeleton shaped like the content, an empty state naming what would fill it, an
error with a retry. The empty state is where a widget earns its keep — "Choose a project in this
widget's settings" tells somebody what to do; a blank card tells them the product is broken.

And handle the widget that is no longer there at all. A saved layout can name a module that was
switched off, uninstalled, or renamed between releases, so `widgetById` returning `undefined` is
ordinary. The frame says so and offers Remove.

## 6. Permission, and disappearing cleanly

Declare `permission` and the widget is absent from the picker for anybody without it, rather than
placed and then refusing them. `widgetsFor` filters on the enabled modules and the caller's
permissions together, which is what makes every trace of a module vanish when a workspace turns it
off — including from layouts that already named it — with no conditional on the dashboard.

Use `when` only for what a permission cannot express, such as a workspace with no projects yet. A
widget vetoed that way stays in the picker, disabled with the reason: hiding it makes the workspace
look emptier than it is and gives no hint what would fill it.

## 7. Whatever the pointer can do, the keyboard can do

A drag is unreachable by keyboard, so the card's menu carries move and size and is the route that is
meant to be found; the drag is the shortcut. Two things this cost:

- **Claim the keys you handle.** The shell binds shortcuts on `window`, so an unhandled key press
  from a widget reaches them — a bare `]` navigated to the issues list in the middle of arranging
  a board. Call `preventDefault` and `stopPropagation` on every key you act on, and leave the
  arrows alone until a card is actually held.
- **Gravity makes "down" a trick question.** The grid compacts upward, so nudging a card into empty
  space below it is undone the instant the layout settles, and ArrowDown looks broken. Downward, the
  move somebody means is "put me after the next one" — fall back to a reorder.

## 8. Verify by running it

```bash
pnpm --filter @kernhq/ui build        # icons and shared components ship from dist
pnpm dev:mock                          # the whole board, no backend
lsof -ti:5173                          # exactly one pid, or two servers fight over the cache
```

Place the widget, configure it, resize it through every size it declares, move it by drag **and** by
the menu **and** by the keyboard, reload, then switch its module off and watch it leave. Then look
at it in `dir="rtl"` and in dark mode.

Type-checking catches none of this. A memoisation bug blanked every card on the board on each
re-render, and passed every check that existed.

## The widget checklist

A widget is done only when **all** of these are true:

- [ ] every figure traced to a procedure that returns it, or the widget cut and said so
- [ ] settings declarative, and `settingsScope` in the query key
- [ ] rows act, and their actions are hidden while editing
- [ ] every declared size looked at; `compact` for a single number
- [ ] loading, empty, error — and the widget-no-longer-available case
- [ ] `permission` declared; `when` only for what permission cannot say
- [ ] menu carries move and size; handled keys claimed
- [ ] messages in en, fa, ar, de
- [ ] exercised in a browser, in both themes and both directions
