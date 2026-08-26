/**
 * Fail when a declared `@kernhq/*` range cannot install what a consumer's CI will resolve.
 *
 *   node scripts/check-ranges.mjs [package.json ...]
 *
 * Three questions, and they fail in three different places:
 *
 *   1. **Can the range reach what is published?** A caret on a 0.x version never crosses a minor:
 *      `^0.7.0` does not admit `0.8.0`. A range that looked right when it was written silently
 *      stops reaching the framework the moment it moves, and the failure appears as missing
 *      exports in a *consumer's* CI — never on the laptop that wrote it, because the umbrella pins
 *      the workspace copies. This broke CI twice on 2026-08-25, in six packages at once.
 *
 *   2. **Is there anything for the range to install at all?** A floor raised past what exists —
 *      `^0.20.0` when 0.10.0 is the latest — used to pass, because a published version *below* the
 *      floor was treated as the publisher's problem. It is not: `pnpm install` answers it with
 *      ERR_PNPM_NO_MATCHING_VERSION, at install time, having built nothing.
 *
 *   3. **Do the modules this package hosts agree with the framework it declares?** Every module
 *      peers `@kernhq/kernel` and `@kernhq/contracts` so that an incompatible pair fails at
 *      install. It does not. pnpm 10 with `auto-install-peers=true` resolved
 *      `@kernhq/module-chat@0.4.8` — which peers `contracts ^0.6.1` — against the `contracts@0.5.2`
 *      the host asked for, exited 0, and printed no warning, in a repository whose `.npmrc` sets
 *      `strict-peer-dependencies=true`. So the check the peer field was added to buy has to be
 *      performed here instead: resolve each hosted `@kernhq/module-*`, read the peers of the exact
 *      version the host's range lands on, and hold the host's own ranges to them.
 *
 *   4. **Does the committed lockfile still agree with the manifest?** This one exists because of
 *      the other three: taking their advice edits a range, and a repository that commits a
 *      `pnpm-lock.yaml` is then out of date with itself. Its next run dies at
 *      ERR_PNPM_OUTDATED_LOCKFILE during install, having built nothing — so the check that was
 *      meant to keep CI green is what turned it red. Eight of the nine lockfile-committing
 *      repositories were in exactly that state on 2026-08-26, every publish failing at install.
 *      A lockfile cannot be refreshed from inside the umbrella; clone the repository somewhere
 *      else and run `pnpm install --lockfile-only` there, then copy it back.
 *
 * Exits 1 and names the range, what is published, and what to write instead.
 */
import { execFileSync } from 'node:child_process'
import { existsSync, readFileSync } from 'node:fs'
import { dirname, join } from 'node:path'

const files = process.argv.slice(2)
if (files.length === 0) {
  console.error('Usage: node scripts/check-ranges.mjs <package.json ...>')
  process.exit(1)
}

const published = new Map()
function latest(name) {
  if (published.has(name)) return published.get(name)
  let version = null
  try {
    version = execFileSync('npm', ['view', name, 'version'], {
      encoding: 'utf8',
      stdio: ['ignore', 'pipe', 'ignore'],
    }).trim()
  } catch {
    // Not published yet is not a failure: a package can legitimately precede its first release.
    version = null
  }
  published.set(name, version)
  return version
}

/**
 * Whether `^x.y.z` / `~x.y.z` / an exact pin admits `version`. Enough for the ranges we write.
 *
 * Honest about a version *below* the floor, which it did not used to be: it answered `true` on the
 * grounds that a range ahead of the registry was the publisher's problem. That let a floor raised
 * past anything published pass lint and then die in CI at ERR_PNPM_NO_MATCHING_VERSION. The reason
 * a range is unsatisfiable is a message, not a verdict — so the verdict is here and the message is
 * at the call site.
 *
 * A range shape this cannot parse answers `null`, meaning "no opinion", so a `>=`, an `||` or a
 * `workspace:` protocol is passed over rather than guessed at.
 */
function admits(range, version) {
  const clean = range.replace(/^[~^]/, '')
  const [rMaj, rMin, rPat] = clean.split('.').map(Number)
  const [vMaj, vMin, vPat] = version.split('-')[0].split('.').map(Number)
  if ([rMaj, rMin, rPat, vMaj, vMin, vPat].some(Number.isNaN)) return null // not a shape we judge
  const ge = vMaj > rMaj || (vMaj === rMaj && (vMin > rMin || (vMin === rMin && vPat >= rPat)))
  if (!ge) return false
  if (range.startsWith('^')) {
    // caret: below 1.0.0 the minor is the breaking position, so it must match exactly
    return rMaj === 0 ? vMaj === 0 && vMin === rMin : vMaj === rMaj
  }
  if (range.startsWith('~')) return vMaj === rMaj && vMin === rMin
  return clean === version
}

/** -1, 0 or 1. Pre-release suffixes are dropped: we do not publish them. */
function cmp(a, b) {
  const pa = a.split('-')[0].split('.').map(Number)
  const pb = b.split('-')[0].split('.').map(Number)
  for (let i = 0; i < 3; i++) if (pa[i] !== pb[i]) return pa[i] > pb[i] ? 1 : -1
  return 0
}

/** The exact version a range lands on today — what a consumer's CI installs. */
const resolved = new Map()
function resolve(name, range) {
  const key = `${name}@${range}`
  if (resolved.has(key)) return resolved.get(key)
  let version = null
  try {
    const out = execFileSync('npm', ['view', key, 'version', '--json'], {
      encoding: 'utf8',
      stdio: ['ignore', 'pipe', 'ignore'],
    }).trim()
    // A range matching several versions prints them all; the highest is the one that installs.
    const parsed = out ? JSON.parse(out) : null
    version = Array.isArray(parsed) ? (parsed[parsed.length - 1] ?? null) : parsed
  } catch {
    version = null
  }
  resolved.set(key, version)
  return version
}

/** The peers of one exact published version, minus the ones it marks optional. */
const peerCache = new Map()
function requiredPeers(name, version) {
  const key = `${name}@${version}`
  if (peerCache.has(key)) return peerCache.get(key)
  let peers = {}
  try {
    const out = execFileSync('npm', ['view', key, 'peerDependencies', 'peerDependenciesMeta', '--json'], {
      encoding: 'utf8',
      stdio: ['ignore', 'pipe', 'ignore'],
    }).trim()
    const doc = out ? JSON.parse(out) : {}
    const meta = doc.peerDependenciesMeta ?? {}
    // An optional peer is one a host is allowed not to have — a server hosting a module does not
    // install svelte, and saying so is the whole reason peerDependenciesMeta exists.
    peers = Object.fromEntries(Object.entries(doc.peerDependencies ?? {}).filter(([p]) => !meta[p]?.optional))
  } catch {
    peers = {}
  }
  peerCache.set(key, peers)
  return peers
}

const SECTIONS = ['dependencies', 'devDependencies', 'peerDependencies']

/**
 * The specifiers a committed lockfile recorded for one dependency.
 *
 * Read as text rather than parsed: the file is enormous, the shape is stable, and the alternative
 * is a YAML dependency in a script whose whole point is to run before anything is installed.
 */
function lockedSpecifiers(lockPath, dep) {
  const lock = readFileSync(lockPath, 'utf8')
  const at = new RegExp(`'?${dep.replace(/[/@]/g, (m) => `\\${m}`)}'?:\\s*\\n\\s*specifier:\\s*(\\S+)`, 'g')
  return new Set([...lock.matchAll(at)].map((m) => m[1].replace(/['"]/g, '')))
}

/** Every `@kernhq/*` range this package declares, section by section. */
function kernRanges(pkg) {
  const out = []
  for (const section of SECTIONS)
    for (const [name, range] of Object.entries(pkg[section] ?? {})) {
      if (!name.startsWith('@kernhq/')) continue
      if (typeof range !== 'string' || range.startsWith('workspace:') || range === '*') continue
      out.push({ section, name, range })
    }
  return out
}

const problems = []
for (const file of files) {
  const pkg = JSON.parse(readFileSync(file, 'utf8'))
  const declared = kernRanges(pkg)

  for (const { section, name, range } of declared) {
    const version = latest(name)
    if (!version) continue
    const ok = admits(range, version)
    if (ok === null || ok) continue
    // Which of the two failures this is decides what the author has to do about it.
    problems.push({
      kind: resolve(name, range) ? 'stale' : 'unsatisfiable',
      file,
      section,
      name,
      range,
      version,
    })
  }

  /*
   * The lockfile check, when there is one to check. `--frozen-lockfile` compares *specifiers*, not
   * resolved versions, so an edited range fails it even though nothing about the tree changed.
   */
  const lockPath = join(dirname(file), 'pnpm-lock.yaml')
  if (existsSync(lockPath))
    for (const { section, name, range } of declared) {
      const locked = lockedSpecifiers(lockPath, name)
      if (locked.size === 0 || [...locked].every((l) => l === range)) continue
      problems.push({ kind: 'lockfile', file, section, name, range, version: [...locked].join(', ') })
    }

  /*
   * The peer check. Only `dependencies` — a module a package merely builds against is not one it
   * hosts, and holding a devDependency to its peers would fail every module repo against itself.
   *
   * Every hosted module's demand for one peer is gathered first, because a host installs exactly
   * one copy of it and the interesting failure is the modules disagreeing with *each other*. Told
   * one module at a time this reads as "lower your range", then the next says "raise it", and an
   * author following the advice oscillates. There is one platform version; a module still asking
   * for last month's has to be republished, and that is what this says.
   */
  const demands = new Map()
  for (const [name, range] of Object.entries(pkg.dependencies ?? {})) {
    if (!name.startsWith('@kernhq/module-')) continue
    if (typeof range !== 'string' || range.startsWith('workspace:') || range === '*') continue
    const version = resolve(name, range)
    if (!version) continue
    for (const [peer, peerRange] of Object.entries(requiredPeers(name, version))) {
      if (!peer.startsWith('@kernhq/')) continue
      if (!demands.has(peer)) demands.set(peer, [])
      demands.get(peer).push({ module: `${name}@${version}`, range: peerRange })
    }
  }

  for (const [peer, wanted] of demands) {
    const own = declared.find((d) => d.name === peer)
    // Not declared at all is not a conflict: pnpm installs the peer itself, unconstrained.
    if (!own) continue

    const mine = resolve(peer, own.range)
    if (!mine) continue
    const asked = wanted.map((w) => ({ ...w, at: resolve(peer, w.range) })).filter((w) => w.at)

    /*
     * One copy gets installed — `mine` — and every module has to accept it. Who has to move is
     * decided by which side is older, and only one of the two answers is ever "lower the host's
     * range": a module still peering last month's contracts is the thing to republish, and the
     * host dropping to meet it would drag every other module down with it.
     */
    const unhappy = asked.filter((w) => admits(w.range, mine) === false)
    if (unhappy.length === 0) continue
    const behind = unhappy.filter((w) => cmp(mine, w.at) > 0)
    const ahead = unhappy.filter((w) => cmp(mine, w.at) <= 0)

    if (ahead.length > 0) {
      // Something needs a newer framework than this host asks for. Raising the range is the fix —
      // unless another module is simultaneously stuck below it, and then nothing here can be right.
      const newest = ahead.reduce((a, b) => (cmp(b.at, a.at) > 0 ? b : a))
      problems.push(
        behind.length > 0
          ? {
              kind: 'conflict',
              file,
              section: own.section,
              name: peer,
              range: own.range,
              version: newest.at,
              via: newest.module,
              laggards: behind.map((l) => `${l.module} peers "${l.range}"`),
            }
          : {
              kind: 'peer',
              file,
              section: own.section,
              name: peer,
              range: own.range,
              version: mine,
              via: newest.module,
              wants: newest.range,
            },
      )
      continue
    }

    problems.push({
      kind: 'stale-module',
      file,
      section: own.section,
      name: peer,
      range: own.range,
      version: mine,
      laggards: behind.map((l) => `${l.module} peers "${l.range}"`),
    })
  }
}

if (problems.length === 0) {
  console.log(`✓ every @kernhq range reaches what is published (${files.length} package.json checked)`)
  process.exit(0)
}

const caret = (v) => (v.startsWith('0.') ? `^${v}` : `^${v.split('.')[0]}.0.0`)

console.error('These ranges cannot install what a consumer will resolve:\n')
for (const p of problems) {
  console.error(`  ${p.file}`)
  if (p.kind === 'lockfile') {
    console.error(
      `    ${p.section}.${p.name}: "${p.range}", but pnpm-lock.yaml still records "${p.version}".`,
    )
    console.error('      --frozen-lockfile compares specifiers, so this fails at install, before')
    console.error('      anything is built. Refresh the lockfile in a clone outside the umbrella:')
    console.error('        pnpm install --lockfile-only')
  } else if (p.kind === 'stale-module') {
    console.error(
      `    ${p.section}.${p.name}: "${p.range}" is right — it installs ${p.version}, and these ` +
        'modules have not caught up:',
    )
    for (const l of p.laggards) console.error(`        ${l}`)
    console.error(`      Republish them against ${p.name}@${p.version}. Lowering this range is not the fix:`)
    console.error('      one platform version, and the host is already on it.')
  } else if (p.kind === 'conflict') {
    console.error(
      `    ${p.section}.${p.name}: the modules this hosts disagree, so no range is right for ` +
        `all of them.\n      ${p.via} needs ${p.version}, but:`,
    )
    for (const l of p.laggards) console.error(`        ${l}`)
    console.error(
      '      A host installs one copy. Republish the module(s) above against the current ' +
        'framework;\n      lowering this range to suit them would take the others with it.',
    )
  } else if (p.kind === 'peer')
    console.error(
      `    ${p.section}.${p.name}: "${p.range}" resolves ${p.version}, but ${p.via} peers ` +
        `"${p.wants}" — write "${caret(p.wants.replace(/^[~^]/, ''))}"`,
    )
  else if (p.kind === 'unsatisfiable')
    console.error(
      `    ${p.section}.${p.name}: "${p.range}"  →  nothing published satisfies it ` +
        `(latest is ${p.version}), write "${caret(p.version)}"`,
    )
  else
    console.error(
      `    ${p.section}.${p.name}: "${p.range}"  →  published ${p.version}, write "${caret(p.version)}"`,
    )
}
console.error('\nA caret on 0.x does not cross a minor. This passes locally because the workspace')
console.error('is pinned, and fails in CI, which installs from the registry — and a peer mismatch')
console.error('does not fail there either: pnpm 10 resolves it silently, which is why it is checked here.')
process.exit(1)
