/**
 * Advance every `@kernhq/*` range in the given package.json files to the newest published set that
 * is compatible with itself.
 *
 *   node scripts/reach.mjs [--write] [--json] <package.json> [<package.json> ...]
 *
 * The nightly release runs this over every service repository before it tags, so a release
 * contains the module work published since the last one. Without it, a caret on a 0.x range never
 * crosses a minor and a cached Docker layer never re-resolves a patch — five releases in a row
 * shipped modules published on 2026-08-27 while npm was six versions ahead.
 *
 * What "compatible" means here:
 *
 *   1. The framework (`@kernhq/contracts`, `kernel`, `ui`, `sdk`, and any other non-module package)
 *      is taken at its newest stable version.
 *   2. Each `@kernhq/module-*` is taken at the newest stable version whose peer ranges on the
 *      framework accept those versions. A module that has not caught up with the framework is held
 *      at the newest version its *current* range reaches, and named in the output — the fix is to
 *      republish the module, never to move the host down.
 *   3. One version per module, across every file given. A module's server runs in `core` and its
 *      client in `shell`; two versions of one module in one release is a contract mismatch.
 *
 * Ranges are written as `^x.y.z`, never as an exact pin: the umbrella workspace links a package
 * when the local version satisfies the range, and an exact pin would silently switch every
 * developer to the registry copy. The lockfile the release commits beside it is what makes the
 * resolution exact.
 *
 * Output (with --json) is what the release notes and the version bump are computed from:
 *
 *   { framework: { name: { from, to } }, modules: { id: { from, to, held } }, files: { path: {...} } }
 *
 * `from` is the newest version the old range reached, which is what a fresh build would have
 * installed — the version an image actually carries is read from the previous release feed by the
 * caller, because a cached layer can be older than that.
 */
import { execFileSync } from 'node:child_process'
import { readFileSync, writeFileSync } from 'node:fs'

const args = process.argv.slice(2)
const write = args.includes('--write')
const asJson = args.includes('--json')
const files = args.filter((a) => !a.startsWith('--'))
if (files.length === 0) {
  console.error('usage: node scripts/reach.mjs [--write] [--json] <package.json> ...')
  process.exit(2)
}

const log = (line) => console.error(line)

// ---------------------------------------------------------------- semver, the parts we need

const parse = (v) => {
  const m = /^(\d+)\.(\d+)\.(\d+)(?:-(.+))?$/.exec(v)
  return m ? { major: +m[1], minor: +m[2], patch: +m[3], pre: m[4] ?? null } : null
}
const cmp = (a, b) => a.major - b.major || a.minor - b.minor || a.patch - b.patch
const gt = (a, b) => cmp(parse(a), parse(b)) > 0

/**
 * Does `version` satisfy `range`? Handles the shapes that appear in this organisation's manifests —
 * `^`, `~`, `>=`, exact, `*`, and `||` between them. Anything else is reported and treated as not
 * satisfied, which errs towards holding a module back rather than shipping an untested pair.
 */
function satisfies(version, range) {
  const v = parse(version)
  if (!v) return false
  return range
    .split('||')
    .map((r) => r.trim())
    .some((r) => {
      if (r === '*' || r === '') return true
      const op = /^(\^|~|>=|>|<=|<|=)?\s*(\d+\.\d+\.\d+)/.exec(r)
      if (!op) {
        log(`  ? cannot read range "${range}", treating as unsatisfied`)
        return false
      }
      const base = parse(op[2])
      const c = cmp(v, base)
      switch (op[1] ?? '=') {
        case '=':
          return c === 0
        case '>=':
          return c >= 0
        case '>':
          return c > 0
        case '<=':
          return c <= 0
        case '<':
          return c < 0
        case '~':
          return c >= 0 && v.major === base.major && v.minor === base.minor
        case '^':
          if (c < 0) return false
          if (base.major > 0) return v.major === base.major
          if (base.minor > 0) return v.major === 0 && v.minor === base.minor
          return v.major === 0 && v.minor === 0 && v.patch === base.patch
      }
      return false
    })
}

// ---------------------------------------------------------------- the registry

const registry = new Map()
function view(spec, field) {
  const key = `${spec} ${field}`
  if (registry.has(key)) return registry.get(key)
  // --prefer-online: `npm view` will otherwise serve metadata hours old from its cache, and a
  // reach that does not see this morning's publish is the exact failure it exists to prevent.
  const out = execFileSync('npm', ['view', spec, field, '--json', '--prefer-online'], {
    encoding: 'utf8',
    stdio: ['ignore', 'pipe', 'pipe'],
  }).trim()
  const value = out ? JSON.parse(out) : null
  registry.set(key, value)
  return value
}

/** Stable versions of a package, newest first. */
function stableVersions(name) {
  const all = view(name, 'versions') ?? []
  return (Array.isArray(all) ? all : [all])
    .filter((v) => parse(v) && !parse(v).pre)
    .sort((a, b) => cmp(parse(b), parse(a)))
}

const newestIn = (name, range) => stableVersions(name).find((v) => satisfies(v, range)) ?? null

// ---------------------------------------------------------------- what the files ask for

const manifests = files.map((path) => ({ path, pkg: JSON.parse(readFileSync(path, 'utf8')) }))
const fields = ['dependencies', 'devDependencies', 'optionalDependencies']
const wanted = new Map() // name -> current range (the first one seen; they should agree)
for (const { pkg } of manifests)
  for (const field of fields)
    for (const [name, range] of Object.entries(pkg[field] ?? {}))
      if (name.startsWith('@kernhq/') && !range.startsWith('workspace:') && !wanted.has(name))
        wanted.set(name, range)

const isModule = (name) => name.startsWith('@kernhq/module-')
const frameworkNames = [...wanted.keys()].filter((n) => !isModule(n))
const moduleNames = [...wanted.keys()].filter(isModule)

// 1. the framework, newest stable
const framework = {}
for (const name of frameworkNames) {
  const to = stableVersions(name)[0]
  if (!to) throw new Error(`${name} has no stable version on the registry`)
  framework[name] = { from: newestIn(name, wanted.get(name)), to }
}

// 2. each module, newest whose peers accept that framework
const modules = {}
for (const name of moduleNames) {
  const id = name.slice('@kernhq/module-'.length)
  const from = newestIn(name, wanted.get(name))
  let to = null
  let held = null
  // Never below what the range reaches today: a reach moves forward or holds still. The newest
  // version whose peers accept the framework can be an old one, and "going back to 0.2.2 because
  // 0.4.6 is a minor behind on its ui peer" is a downgrade nobody asked for.
  const candidates = stableVersions(name).filter((v) => !from || v === from || gt(v, from))
  for (const candidate of candidates.slice(0, 25)) {
    const peers = view(`${name}@${candidate}`, 'peerDependencies') ?? {}
    const unmet = Object.entries(peers)
      .filter(([peer]) => peer.startsWith('@kernhq/'))
      .filter(([peer, range]) => framework[peer] && !satisfies(framework[peer].to, range))
    if (unmet.length === 0) {
      to = candidate
      break
    }
    if (candidate === stableVersions(name)[0])
      held = unmet.map(([peer, range]) => `${peer}@${range} does not accept ${framework[peer].to}`).join('; ')
  }
  if (!to) {
    // nothing published accepts the framework: keep what the range reaches today and say so
    to = from
    held = held ?? 'no published version accepts the newest framework'
  } else if (held && to !== stableVersions(name)[0]) {
    held = `${stableVersions(name)[0]} held back: ${held}`
  } else {
    held = null
  }
  modules[id] = { name, from, to, held }
}

// 3. write the ranges
const perFile = {}
for (const { path, pkg } of manifests) {
  const changes = {}
  for (const field of fields) {
    for (const [name, range] of Object.entries(pkg[field] ?? {})) {
      if (!name.startsWith('@kernhq/') || range.startsWith('workspace:')) continue
      const target = isModule(name) ? modules[name.slice('@kernhq/module-'.length)].to : framework[name].to
      const next = `^${target}`
      if (next !== range) {
        changes[name] = { from: range, to: next }
        pkg[field][name] = next
      }
    }
  }
  perFile[path] = changes
  if (write && Object.keys(changes).length) writeFileSync(path, `${JSON.stringify(pkg, null, 2)}\n`)
}

const result = { framework, modules, files: perFile }

for (const [name, { from, to }] of Object.entries(framework))
  log(`  ${name}: ${from ?? '?'} -> ${to}${from === to ? ' (unchanged)' : ''}`)
for (const [id, { from, to, held }] of Object.entries(modules))
  log(
    `  module ${id}: ${from ?? '?'} -> ${to}${from === to ? ' (unchanged)' : ''}${held ? `  ! ${held}` : ''}`,
  )
for (const [path, changes] of Object.entries(perFile))
  log(`  ${path}: ${Object.keys(changes).length} range(s) ${write ? 'rewritten' : 'would change'}`)

if (asJson) console.log(JSON.stringify(result, null, 2))
