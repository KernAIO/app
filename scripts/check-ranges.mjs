/**
 * Fail when a declared `@kernhq/*` range cannot reach what is published.
 *
 *   node scripts/check-ranges.mjs [package.json ...]
 *
 * A caret on a 0.x version never crosses a minor: `^0.7.0` does not admit `0.8.0`. So a range that
 * looked right when it was written silently stops reaching the framework the moment it moves, and
 * the failure appears as missing exports in a *consumer's* CI — never on the laptop that wrote it,
 * because the umbrella pins the workspace copies.
 *
 * This broke CI twice on 2026-08-25 alone, in six packages at once. With every module in its own
 * repository there is no single place left to fix it, so each repository checks itself.
 *
 * Exits 1 and names the range, what is published, and what to write instead.
 */
import { execFileSync } from 'node:child_process'
import { readFileSync } from 'node:fs'

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

/** Whether `^x.y.z` / `~x.y.z` / an exact pin admits `version`. Enough for the ranges we write. */
function admits(range, version) {
  const clean = range.replace(/^[~^]/, '')
  const [rMaj, rMin, rPat] = clean.split('.').map(Number)
  const [vMaj, vMin, vPat] = version.split('-')[0].split('.').map(Number)
  if ([rMaj, rMin, rPat, vMaj, vMin, vPat].some(Number.isNaN)) return true // not a shape we judge
  const ge = vMaj > rMaj || (vMaj === rMaj && (vMin > rMin || (vMin === rMin && vPat >= rPat)))
  if (!ge) return true // published is older than the floor; that is the publisher's problem, not this
  if (range.startsWith('^')) {
    // caret: below 1.0.0 the minor is the breaking position, so it must match exactly
    return rMaj === 0 ? vMaj === 0 && vMin === rMin : vMaj === rMaj
  }
  if (range.startsWith('~')) return vMaj === rMaj && vMin === rMin
  return clean === version
}

const problems = []
for (const file of files) {
  const pkg = JSON.parse(readFileSync(file, 'utf8'))
  for (const section of ['dependencies', 'devDependencies', 'peerDependencies']) {
    for (const [name, range] of Object.entries(pkg[section] ?? {})) {
      if (!name.startsWith('@kernhq/')) continue
      if (typeof range !== 'string' || range.startsWith('workspace:') || range === '*') continue
      const version = latest(name)
      if (!version || admits(range, version)) continue
      problems.push({ file, section, name, range, version })
    }
  }
}

if (problems.length === 0) {
  console.log(`✓ every @kernhq range reaches what is published (${files.length} package.json checked)`)
  process.exit(0)
}

console.error('These ranges cannot install the published version:\n')
for (const p of problems) {
  const suggest = p.version.startsWith('0.') ? `^${p.version}` : `^${p.version.split('.')[0]}.0.0`
  console.error(`  ${p.file}`)
  console.error(`    ${p.section}.${p.name}: "${p.range}"  →  published ${p.version}, write "${suggest}"`)
}
console.error('\nA caret on 0.x does not cross a minor. This passes locally because the workspace')
console.error('is pinned, and fails in CI, which installs from the registry.')
process.exit(1)
