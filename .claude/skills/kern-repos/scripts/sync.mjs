#!/usr/bin/env node
/**
 * Regenerates references/inventory.md — the map of every KernAIO repository.
 *
 *   node .claude/skills/kern-repos/scripts/sync.mjs
 *
 * The org is the source of truth for which repositories exist (via `gh`); the local
 * checkouts are the source of truth for what is inside them (package name, port,
 * published packages). Anything the script cannot see, it says so rather than guessing.
 *
 * Run it in the same commit as any change to the set of repositories. See SKILL.md.
 */
import { execFileSync } from 'node:child_process'
import { existsSync, readdirSync, readFileSync, writeFileSync } from 'node:fs'
import { dirname, join, resolve } from 'node:path'
import { fileURLToPath } from 'node:url'

const here = dirname(fileURLToPath(import.meta.url))
const skillDir = resolve(here, '..')

/**
 * The umbrella is the repository that holds selfhost/. Walk up from this file and try each
 * ancestor, and each ancestor's `kern/`, because this skill is also copied to a `.claude`
 * one level above the umbrella and the relative depth is not the same in both places.
 */
function findUmbrella(start) {
  let dir = start
  for (let i = 0; i < 6; i++) {
    for (const candidate of [dir, join(dir, 'kern')]) {
      if (existsSync(join(candidate, 'selfhost', 'docker-compose.yml'))) return candidate
    }
    const parent = dirname(dir)
    if (parent === dir) break
    dir = parent
  }
  console.error('Could not find the umbrella repository (the one holding selfhost/) above')
  console.error(`  ${start}`)
  console.error('Run this from inside the Kern workspace. inventory.md was left alone.')
  process.exit(1)
}

const umbrella = findUmbrella(skillDir)
const workspace = resolve(umbrella, '..') // the directory holding kern/ and its siblings

const ORG = 'KernAIO'

function gh(args) {
  try {
    return execFileSync('gh', args, { encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'] })
  } catch (error) {
    console.error(`\ngh failed: ${error.stderr?.toString().trim() || error.message}`)
    console.error('Sign in with `gh auth login`, then run this again. inventory.md was left alone.')
    process.exit(1)
  }
}

function readJson(path) {
  try {
    return JSON.parse(readFileSync(path, 'utf8'))
  } catch {
    return null
  }
}

/** Where a repository is checked out, if it is. */
function findCheckout(name) {
  if (name === 'kern') return umbrella
  const candidates = [join(umbrella, 'repos', name), join(workspace, name)]
  return candidates.find((path) => existsSync(join(path, '.git'))) ?? null
}

/**
 * The port a repo binds. Services declare `PORT=` in .env.example; the front ends pass
 * `--port` to their dev server. Check both, in that order.
 */
function findPort(checkout, pkg) {
  const env = checkout ? tryRead(join(checkout, '.env.example')) : null
  const fromEnv = env && /^PORT=(\d{4})$/m.exec(env)
  if (fromEnv) return fromEnv[1]
  for (const script of Object.values(pkg?.scripts ?? {})) {
    const match = /--port[= ](\d{4})/.exec(script)
    if (match) return match[1]
  }
  return null
}

function tryRead(path) {
  try {
    return readFileSync(path, 'utf8')
  } catch {
    return null
  }
}

/** Packages a workspace repo publishes to npm. */
function findPackages(checkout) {
  const dir = join(checkout, 'packages')
  if (!existsSync(dir)) return []
  return readdirSync(dir, { withFileTypes: true })
    .filter((entry) => entry.isDirectory())
    .map((entry) => readJson(join(dir, entry.name, 'package.json')))
    .filter((pkg) => pkg && !pkg.private)
    .map((pkg) => pkg.name)
    .sort()
}

const repos = JSON.parse(
  gh(['repo', 'list', ORG, '--limit', '100', '--json', 'name,description,visibility,isArchived,url']),
)
  .filter((repo) => repo.name !== '.github')
  .sort((a, b) => a.name.localeCompare(b.name))

const rows = repos.map((repo) => {
  const checkout = findCheckout(repo.name)
  const pkg = checkout ? readJson(join(checkout, 'package.json')) : null
  return {
    ...repo,
    checkout,
    pkgName: pkg?.name ?? null,
    port: findPort(checkout, pkg),
    packages: checkout ? findPackages(checkout) : [],
    private: pkg?.private === true,
  }
})

const relative = (path) => (path ? path.replace(`${workspace}/`, '') : null)

const table = [
  '| Repository | Visibility | What it holds | Checked out at | Port |',
  '|---|---|---|---|---|',
  ...rows.map((r) => {
    const where = r.checkout ? `\`${relative(r.checkout)}\`` : '_not cloned here_'
    return `| [\`${r.name}\`](${r.url}) | ${r.visibility.toLowerCase()} | ${r.description ?? '—'} | ${where} | ${r.port ?? '—'} |`
  }),
].join('\n')

const published = rows
  .filter((r) => r.packages.length)
  .map((r) => `**${r.name}** publishes:\n${r.packages.map((p) => `- \`${p}\``).join('\n')}`)
  .join('\n\n')

const ports = rows
  .filter((r) => r.port)
  .sort((a, b) => Number(a.port) - Number(b.port))
  .map((r) => `${r.name} ${r.port}`)
  .join(' · ')

// Services live in the 4000 band, one hundred apart. The front ends sit outside it on
// their framework's own default, so they do not push the next service port along.
const servicePorts = rows.map((r) => Number(r.port)).filter((p) => p >= 4000 && p < 5000)
const nextPort = servicePorts.length ? Math.max(...servicePorts) + 100 : 4000

const missing = rows.filter((r) => !r.checkout).map((r) => r.name)

const stamp = new Date().toISOString().slice(0, 10)

const out = `<!--
  GENERATED FILE — do not edit by hand.
  Regenerate with: node .claude/skills/kern-repos/scripts/sync.mjs
  Everything here is read from the ${ORG} organisation and the local checkouts.
-->

# The KernAIO repositories

${repos.length} repositories, last synced ${stamp}.

${table}

## Ports

${ports}

Services sit in the 4000 band, one hundred apart. Next free: **${nextPort}** — claim it in the
repo's \`.env.example\` (\`PORT=\`) and in the umbrella \`CLAUDE.md\`, then re-run the sync.

## Published packages

${published || '_No local checkout exposes a `packages/` directory._'}
${
  missing.length
    ? `\n## Not cloned on this machine\n\n${missing.map((n) => `- \`${n}\` — \`bash scripts/dev-setup.sh\` clones the workspace repos; anything outside it is cloned by hand.`).join('\n')}\n`
    : ''
}`

const target = join(skillDir, 'references', 'inventory.md')
writeFileSync(target, out)
console.log(`Wrote ${target}`)
console.log(
  `${repos.length} repositories · ${rows.filter((r) => r.checkout).length} cloned here · next free port ${nextPort}`,
)
