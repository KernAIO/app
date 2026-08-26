---
name: kern-language
description: How Kern speaks more than one language — writing message keys, translating so the result reads as the target language rather than as English in disguise, plurals and digits through Intl, adding a locale, and the check that stops a gap reaching a user. Trigger whenever adding or changing a user-facing string, translating, adding a language, or reviewing anything under repos/shell/messages.
---

# Kern's languages

Kern ships English, Persian, Arabic and German, and promises them equally. A missing translation is
not a blank — Paraglide compiles it into a silent alias to English, so a locale can be missing a
thousand keys and every build stays green. Nothing here is caught by the compiler.

`kern-ui` §6 owns the four rules about *screens*: strings go through Paraglide, keys go in every
locale file, logical properties, verify both themes. This is about the strings themselves.

## 1. Add the key in English and Persian, in the same commit

```bash
# messages/en.json and messages/fa.json, sorted, $schema first
pnpm i18n                                # compile, or m.your_key() does not exist
node scripts/check-i18n.mjs              # also runs inside pnpm lint
```

English and Persian are what `REQUIRED` in `scripts/check-i18n.mjs` fails on. Arabic and German are
reported and do not fail, until they reach parity and join the list. Adding a key to English alone
passes `typecheck` and ships an English string to a Persian reader.

Delete a key in the commit that removes its last use. Renaming three workflow section titles one
afternoon orphaned `tracker_workflow_statuses`, `tracker_workflow_transitions` and
`tracker_workflow_used_by_label`, and removing two sidebar groups orphaned `nav_modules` — four dead
keys in a day, unnoticed. The check lists unreferenced keys but never fails on them: a key may
legitimately land before its screen, which is what 29 `admin_*` keys were doing at the time.

## 2. Translate the meaning, not the words

A translation that maps English word for word is wrong even when every word is right.

- **Recast the clause order.** `tracker_settings_import_hint` puts the subordinate clause first in
  Persian — «تا نگویید هر ستون چیست، چیزی وارد نمی‌شود» — the opposite of the English.
- **Replace idioms, do not carry them.** "You're all caught up" → «همه‌چیز به‌روز است». Translated
  literally it means nothing.
- **Add what the target grammar needs.** "Search {workspace}…" → «جستجو در {workspace}…»: Persian
  requires the preposition English does not have.
- **Move the placeholder.** "{name} settings" → «تنظیمات {name}». Head-initial, so the order flips.
- **Drop what the target does not say.** "Please try again" → «دوباره تلاش کنید».
- **Check the frame the string lands in.** `invite_shares_with_you` was a correct translation and
  ungrammatical in place: English "shares {n} workspaces with you" is a predicate appended after a
  name, and the Persian was a noun phrase, so the row read "علی ۳ فضای کاری مشترک با شما" with no
  verb. Read the sentence the string completes, not the string.

One English noun gets one translation, everywhere. `tracker_issues_count` and
`tracker_planning_issue_count` are the same English string, "{count} issues", and were rendered
«{count} کار» and «{count} مورد». Check `messages/GLOSSARY.md` before inventing a word for a product
noun, and add it there when you settle one.

If you cannot write a language, say so in your report. Do not leave it silently English — the check
will not fail on it, and nobody will notice until a reader does.

**Do not ask permission per locale, per area or per batch.** Translation is long, repetitive work and
stopping to check in turns one task into forty. Fill a language end to end, run the check, and report
once at the end: which locales you wrote, which you could not, and what you verified. Ask only when a
decision is genuinely the maintainer's — a term that changes what the product calls something, or a
locale nobody on the team reads well enough to review.

## 3. Counts are variant messages, never `{count}` in a string

A flat string is wrong in every language that inflects. English said "1 issues" for a year.

```json
"tracker_issues_count": [{
  "declarations": ["input count", "local n = count: number", "local countPlural = count: plural"],
  "selectors": ["countPlural"],
  "match": { "countPlural=one": "{n} issue", "countPlural=other": "{n} issues" }
}]
```

`local n = count: number` is what puts the number through `Intl`, and the only reason a Persian
screen reads «۱۱ کار» rather than "11 کار". Callers are unchanged — the input is still `count`.

**A branch that is missing at runtime renders the message key.** Not English: the key. Arabic uses
six categories, so a translator who writes the `one`/`other` pair English needs breaks every count
from two upward while 1 still looks right. Persian needs `one` *and* `other` even though both read
the same. Check what a locale actually uses:

```bash
node -e "console.log(new Intl.PluralRules('ar').resolvedOptions().pluralCategories.join(', '))"
```

## 4. Everything a person reads goes through `Intl`

`$lib/format.ts` already has these; reuse rather than re-deriving. `relativeTime`, `formatDate`,
`formatDateTime`, `localTime`, `formatCount` (which also caps a badge at "99+").

- A date range is `Intl.DateTimeFormat.formatRange`, never two dates and a dash — hand-built, it
  reads backwards in RTL, with the earliest date to the right of the latest.
- Time-zone cities come from CLDR through `scripts/gen-timezone-cities.mjs`, not from `Intl`, which
  localises a zone's name but never its city. Never translate those by hand.
- Under `[dir="rtl"]` the mono token resolves to the sans stack: DM Mono has no Arabic glyphs, and a
  monospace Arabic face draws letters in isolated forms — «فضای کاری» came out unjoined and spaced
  like code. Metadata is carried by size, weight and colour instead.

## 5. Adding a language

```bash
pnpm i18n:new tr          # declares it and prints the four remaining steps
pnpm i18n:fill tr         # writes every gap as TODO, plural stubs shaped for tr's categories
pnpm i18n:missing tr      # what is left, with the English beside it
```

A locale lives in five places, which is why doing it by hand goes wrong: `project.inlang/settings.json`,
`messages/<locale>.json`, `localeNames` in `settings/appearance/+page.svelte` (or the picker shows a
bare code), the `RTL` set in `src/routes/+layout.svelte`, and `src/lib/i18n/timezone-cities/<locale>.json`.
Add it to `REQUIRED` in `scripts/check-i18n.mjs` the day it reaches parity, and CI keeps it there.

A contributor improving one language should need none of this: they edit one JSON file, run
`pnpm i18n:missing <locale>` to see what is left, and nothing else.

## 6. Verify by running it

Never by type-checking. Paraglide type-checks perfectly with a thousand keys missing.

```bash
node scripts/check-i18n.mjs              # parity, placeholders, orphans, plural coverage
pnpm exec vitest run src/lib/i18n        # plurals per locale, against the compiled catalogue
pnpm exec biome format --write messages/ # a script-written catalogue fails lint on whitespace alone
pnpm dev:mock                            # then Settings → Appearance, and walk the screens
```

Switch to each locale and read the screens you touched — not the strings in a list. A string is
right or wrong in the sentence it completes and the width it has. For `fa` and `ar`, confirm the
layout still holds: `document.documentElement.dir` follows the locale from `src/routes/+layout.svelte`.

State plainly in your report which locales you wrote, which you could not, and what you exercised.
