#!/usr/bin/env node
/**
 * i18n coverage across Kern's user-facing strings.
 *
 * Surfaces:
 *  - shell:   shell/messages/<locale>.json — Paraglide sources, nested JSON
 *  - modules: <module-repo>/src/client/i18n.ts — five `export const <locale>` blocks
 *             (Record<string, Message>; values are strings or {one,other} plural objects)
 *
 * A string counts as UNTRANSLATED when the locale's value is identical to the English value
 * (a copy, not a translation). MISSING means the key is absent from that locale's bundle.
 * Both are reported; leaves are counted individually, so a plural entry is two strings.
 *
 * Three kinds of slot are dropped before anything is counted, because no locale can translate
 * them: inlang plumbing (a variant message's `declarations` and `selectors`, and the `$schema`
 * line), prose-free values (an ellipsis, a separator, a line built only from placeholders), and
 * the input formats enumerated in EXAMPLE_VALUES.
 *
 * What the table still flags is by design, so classify before briefing a translation batch. An
 * audit of every flagged slot on 2026-09-02 found only brand and product names (Quire, Kern,
 * Cursor, VS Code, Claude Code, ChatGPT, Codex), words German writes the same way or has borrowed
 * (Name, Status, Filter, Dashboard, Workspace, Backlog, Epic — the bundle's own usage is the
 * arbiter, and the register differs per module: hr-de is Sie-form, tracker-de and quire-de are
 * du-form), and module-template's English-only starter strings, which its README says are
 * deliberate. The genuinely translatable residue was 8 strings plus one wrong value, all shipped.
 *
 * Usage: node scripts/i18n-coverage.mjs [--root /path/to/kern]
 * Prints a markdown table plus per-module detail. Exit 1 only when a surface cannot be read.
 * The numbers this prints are the ones ROADMAP.md's slice 5 cites — refresh it when they move.
 */

import { existsSync, readdirSync, readFileSync } from 'node:fs'
import { dirname, join, resolve } from 'node:path'
import { fileURLToPath } from 'node:url'

const scriptDir = dirname(fileURLToPath(import.meta.url))
const argRoot = process.argv.indexOf('--root')
const ROOT = argRoot > -1 ? resolve(process.argv[argRoot + 1]) : resolve(scriptDir, '..', '..')

const LOCALES = ['de', 'fa', 'ar', 'tr']
const EXIT_BAD = (msg) => {
  console.error(`i18n-coverage: ${msg}`)
  process.exit(1)
}

/** Leaf strings of a JSON-ish value; plural objects count one leaf per form. */
const leaves = (v) =>
  typeof v === 'string' ? [v] : v && typeof v === 'object' ? Object.values(v).flatMap(leaves) : []

/** Flatten to key -> canonical value (JSON string), so comparison is deep. */
const flat = (v, prefix = '') => {
  const out = {}
  if (typeof v === 'string') out[prefix] = v
  else if (v && typeof v === 'object')
    for (const [k, sub] of Object.entries(v)) Object.assign(out, flat(sub, prefix ? `${prefix}.${k}` : k))
  return out
}

/**
 * Leaves of an inlang variant message that carry no human-readable text.
 *
 * A shell plural is an array of one message object whose `declarations` ("input count",
 * "local n = count: number") and `selectors` ("countPlural") are ICU logic, identical in every
 * locale by design — only the `match` values are prose. Counting them as "still English" put 124
 * phantom strings in German's untranslated column, a false alarm larger than the real gap.
 * The file's top-level `$schema` is the same thing one level up: an editor hint holding the same
 * URL in all five bundles.
 */
const isInlangStructure = (key) => key === '$schema' || /\.(declarations|selectors)\.\d+$/.test(key)

/**
 * Values that are an input format rather than a sentence. The user types these back, so a
 * translated one would be wrong rather than merely English — and nothing mechanical can tell
 * "1h30m" from a phrase, so they are named.
 */
const EXAMPLE_VALUES = new Set([
  // KQL syntax. The query language the parser accepts is the same in every locale.
  'tracker.kql_placeholder',
  // "1h30m" is what parseDuration reads, and the units stay h/m: a Persian ۱س۳۰د shipped once and
  // was reverted, because the parser rejects it.
  'tracker.time_placeholder',
  // "eng-core" shows the channel-slug format, not a channel anybody has.
  'chat.channel_name_placeholder',
])

/**
 * What is left of a value once ICU placeholders, punctuation, symbols and digits are removed.
 * Nothing left means it is a template — "…", "{name} · {date}", "— {n} —" — and a locale repeating
 * it verbatim is not an untranslated string, because there is no language in it.
 */
const prose = (v) =>
  String(v)
    .replace(/\{[^}]*\}/g, ' ')
    .replace(/[\s\p{P}\p{S}\d·—–-]/gu, '')

/**
 * Flat keys to leave out of every locale's map for one surface, decided from the English bundle:
 * the enumerated input examples, and every entry with no prose in it. A plural qualifies only when
 * all of its forms do — one translatable form makes the whole entry translatable.
 */
function excludedKeys(en, isStructural = () => false) {
  const drop = new Set()
  for (const [key, value] of Object.entries(en)) {
    const entries = Object.entries(flat(value, key)).filter(([k]) => !isStructural(k))
    if (!entries.length) continue
    if (EXAMPLE_VALUES.has(key) || entries.every(([, v]) => !prose(v))) for (const [k] of entries) drop.add(k)
  }
  return drop
}

/** shell/messages/<locale>.json */
function readShell() {
  const dir = join(ROOT, 'shell', 'messages')
  if (!existsSync(dir)) return null
  const raw = {}
  for (const loc of ['en', ...LOCALES]) {
    const file = join(dir, `${loc}.json`)
    if (!existsSync(file)) EXIT_BAD(`missing ${file}`)
    raw[loc] = JSON.parse(readFileSync(file, 'utf8'))
  }
  const drop = excludedKeys(raw.en, isInlangStructure)
  const byLocale = {}
  // Dropped from English too, so the key totals and the untranslated counts stay comparable.
  for (const loc of ['en', ...LOCALES])
    byLocale[loc] = Object.fromEntries(
      Object.entries(flat(raw[loc])).filter(([k]) => !isInlangStructure(k) && !drop.has(k)),
    )
  return { name: 'shell (Paraglide)', byLocale }
}

/**
 * Module bundles are TS, not JSON, so extract the five exported consts textually: find
 * `export const <locale>: Record<string, Message> = {`, brace-match to the closing `}`, and
 * evaluate the block as an object literal. The blocks are plain data (quoted keys, string or
 * plural-object values), which is what makes this safe; anything else in the file is ignored.
 */
function extractLocaleBlocks(ts) {
  const out = {}
  for (const loc of ['en', ...LOCALES]) {
    // Some modules export the locale consts, some keep them module-private (`const de = {…}`),
    // so match both. \b keeps us away from names like `denmark` or `translation`.
    const start = ts.search(new RegExp(`(export )?const ${loc}\\b[^=]*=\\s*\\{`))
    if (start === -1) continue
    const open = ts.indexOf('{', start)
    let depth = 0
    let end = -1
    for (let i = open; i < ts.length; i++) {
      if (ts[i] === '{') depth++
      else if (ts[i] === '}') {
        depth--
        if (depth === 0) {
          end = i
          break
        }
      }
    }
    if (end === -1) EXIT_BAD(`unbalanced braces in a ${loc} block`)
    const body = ts.slice(open, end + 1)
    // eslint-disable-next-line no-new-func
    out[loc] = new Function(`return (${body})`)()
  }
  return out
}

function readModule(repo) {
  // Most modules keep the bundles in src/client/i18n.ts; some (module-hr) split the strings into
  // a sibling messages.ts that i18n.ts re-exports. Use the first file that yields locale blocks.
  for (const rel of ['src/client/i18n.ts', 'src/client/messages.ts']) {
    const file = join(ROOT, repo, rel)
    if (!existsSync(file)) continue
    const blocks = extractLocaleBlocks(readFileSync(file, 'utf8'))
    if (!blocks.en) continue
    const drop = excludedKeys(blocks.en)
    const byLocale = {}
    for (const loc of ['en', ...LOCALES])
      byLocale[loc] = Object.fromEntries(
        Object.entries(flat(blocks[loc] ?? {})).filter(([k]) => !drop.has(k)),
      )
    return { name: repo, byLocale }
  }
  return null
}

const surfaces = []
const shell = readShell()
if (shell) surfaces.push(shell)
const repos = readdirSync(ROOT)
  .filter((d) => /^module-/.test(d))
  .sort()
for (const repo of repos) {
  const mod = readModule(repo)
  if (mod) surfaces.push(mod)
  else console.error(`i18n-coverage: skipped ${repo} (no src/client/i18n.ts)`)
}
if (!surfaces.length) EXIT_BAD('no surfaces found — is --root the kern workspace?')

const pct = (n, d) => (d ? ((100 * (d - n)) / d).toFixed(1) : '100.0')
const rows = []
const totals = { keys: 0 }
for (const loc of LOCALES) totals[loc] = 0

for (const s of surfaces) {
  const en = s.byLocale.en
  const row = { name: s.name, keys: Object.keys(en).length }
  for (const loc of LOCALES) {
    const locMap = s.byLocale[loc] ?? {}
    const missing = Object.keys(en).filter((k) => !(k in locMap)).length
    const copied = Object.keys(en).filter((k) => k in locMap && locMap[k] === en[k]).length
    const miss = missing + copied
    row[loc] = miss
    row[`${loc}_detail`] = `${missing} missing + ${copied} copied from en`
    totals[loc] += miss
  }
  totals.keys += row.keys
  rows.push(row)
}

console.log('# i18n coverage\n')
console.log(`| surface | keys | ${LOCALES.map((l) => `${l} untranslated`).join(' | ')} |`)
console.log(`|---|---|${LOCALES.map(() => '---|').join('')}`)
for (const r of rows) {
  console.log(
    `| ${r.name} | ${r.keys} | ${LOCALES.map((l) => `${r[l]} (${pct(r[l], r.keys)}%)`).join(' | ')} |`,
  )
}
console.log(
  `| **all** | **${totals.keys}** | ` +
    LOCALES.map((l) => `**${totals[l]} (${pct(totals[l], totals.keys)}%)**`).join(' | ') +
    ' |',
)
console.log(
  '\nEach cell: keys missing from the locale plus keys whose value is still the English copy.',
  'Percentage is translated coverage.',
)
for (const r of rows) {
  console.log(`\n${r.name}:`)
  for (const l of LOCALES) console.log(`  ${l}: ${r[`${l}_detail`]}`)
}
