/**
 * Move one module package out of `KernAIO/modules` into its own repository.
 *
 *   node scripts/split-module.mjs <id> [--push]
 *
 * Every first-party module lives in its own repository so that it has the same shape as one written
 * by somebody outside this organisation. They are the reference implementations — "each one written
 * the way yours would be" — and a reference that lives somewhere structurally special is not one.
 *
 * History travels with the package (`git subtree split`), because a public repository's history is
 * part of what people judge it by.
 *
 * Without `--push` it prepares the repository under `.split/<id>` and stops, so the result can be
 * built and tested before anything is created. That order matters: a public repository whose first
 * CI run fails is worse than one that does not exist yet.
 */
import { execFileSync } from 'node:child_process'
import { cpSync, existsSync, mkdirSync, readFileSync, rmSync, writeFileSync } from 'node:fs'
import { dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'

const root = join(dirname(fileURLToPath(import.meta.url)), '..')
const id = (process.argv[2] ?? '').trim()
const push = process.argv.includes('--push')
if (!id) {
  console.error('Usage: node scripts/split-module.mjs <id> [--push]')
  process.exit(1)
}

const MODULES = join(root, 'repos/modules')
const pkgDir = join(MODULES, 'packages', id)
if (!existsSync(pkgDir)) {
  console.error(`No package at repos/modules/packages/${id}`)
  process.exit(1)
}

/** `stdio: 'ignore'` makes execFileSync return null, so trim what came back rather than the call. */
const run = (cmd, args, opts = {}) => {
  const out = execFileSync(cmd, args, { encoding: 'utf8', stdio: ['ignore', 'pipe', 'inherit'], ...opts })
  return typeof out === 'string' ? out.trim() : ''
}

const pkg = JSON.parse(readFileSync(join(pkgDir, 'package.json'), 'utf8'))
const repo = pkg.name.replace('@kernhq/', '')
const dest = join(root, '.split', repo)

console.log(`${pkg.name}  →  KernAIO/${repo}`)

// ---------------------------------------------------------------- history
const branch = `split/${repo}`
try {
  run('git', ['branch', '-D', branch], { cwd: MODULES, stdio: 'ignore' })
} catch {}
run('git', ['subtree', 'split', `--prefix=packages/${id}`, '-b', branch], { cwd: MODULES, stdio: 'ignore' })
rmSync(dest, { recursive: true, force: true })
mkdirSync(dirname(dest), { recursive: true })
run('git', ['clone', '-q', '--branch', branch, `file://${MODULES}`, dest])
run('git', ['checkout', '-q', '-B', 'main'], { cwd: dest })
console.log(`  history: ${run('git', ['rev-list', '--count', 'HEAD'], { cwd: dest })} commits`)

// ---------------------------------------------------------------- furniture
for (const f of [
  'CLA.md',
  'CODE_OF_CONDUCT.md',
  'CONTRIBUTING.md',
  'SECURITY.md',
  'biome.json',
  'renovate.json',
  'turbo.json',
  'tsconfig.base.json',
  '.editorconfig',
  '.gitignore',
  '.npmrc',
  '.nvmrc',
])
  if (existsSync(join(MODULES, f))) cpSync(join(MODULES, f), join(dest, f))

// An AGPL module keeps the product's licence; the repository root carries it now.
if (!existsSync(join(dest, 'LICENSE'))) cpSync(join(MODULES, 'LICENSE'), join(dest, 'LICENSE'))

// Each repository checks its own ranges; there is no shared place left to do it once.
mkdirSync(join(dest, 'scripts'), { recursive: true })
cpSync(join(root, 'scripts/check-ranges.mjs'), join(dest, 'scripts/check-ranges.mjs'))

// ---------------------------------------------------------------- package.json
// The package is the repository root now: no workspace above it to inherit from.
const out = { ...pkg }
out.packageManager = JSON.parse(readFileSync(join(MODULES, 'package.json'), 'utf8')).packageManager
out.engines = { node: '>=24' }
out.repository = { type: 'git', url: `git+https://github.com/KernAIO/${repo}.git` }
out.homepage = `https://github.com/KernAIO/${repo}#readme`
out.scripts = {
  ...out.scripts,
  lint: 'biome check . && node scripts/check-ranges.mjs package.json',
  format: 'biome check --write .',
}
out.devDependencies = { ...out.devDependencies, '@biomejs/biome': '^2.0.0' }
writeFileSync(join(dest, 'package.json'), `${JSON.stringify(out, null, 2)}\n`)

for (const f of ['tsconfig.json', 'tsconfig.client.json'])
  if (existsSync(join(dest, f)))
    writeFileSync(
      join(dest, f),
      readFileSync(join(dest, f), 'utf8').replaceAll('"../../tsconfig.base.json"', '"./tsconfig.base.json"'),
    )

// ---------------------------------------------------------------- CI
const needsDb = existsSync(join(dest, 'migrations'))
mkdirSync(join(dest, '.github/workflows'), { recursive: true })
writeFileSync(
  join(dest, '.github/workflows/ci.yml'),
  `name: CI
on:
  push: { branches: [main] }
  pull_request:
concurrency:
  group: "ci-\${{ github.ref }}"
  cancel-in-progress: true
permissions: { contents: read }
jobs:
  check:
    runs-on: ubuntu-latest
${
  needsDb
    ? `    env:
      # 127.0.0.1, never localhost: a runner resolves localhost to ::1 first, where the published
      # port is not listening, and the client does not retry over IPv4.
      DATABASE_URL: postgres://kern:kern@127.0.0.1:5432/kern
    services:
      # The suites create a scratch database per file, apply the migrations and prove row-level
      # security as an unprivileged role. Nothing is mocked, so without this they fail to start
      # rather than quietly passing.
      postgres:
        image: pgvector/pgvector:pg18
        env:
          POSTGRES_USER: kern
          POSTGRES_PASSWORD: kern
          POSTGRES_DB: kern
        ports: ['5432:5432']
        options: >-
          --health-cmd "pg_isready -U kern"
          --health-interval 5s
          --health-timeout 5s
          --health-retries 20
`
    : ''
}    steps:
      - uses: actions/checkout@v4
      - uses: pnpm/action-setup@v4
      # No registry-url: it writes an .npmrc with a placeholder token, and npm answers a bad token
      # with 404 — so every public package appears to vanish at install.
      - uses: actions/setup-node@v4
        with: { node-version: 24 }
      - run: if [ -f pnpm-lock.yaml ]; then pnpm install --frozen-lockfile; else pnpm install; fi
      # lint includes check-ranges: a caret on 0.x does not cross a minor, so a range that cannot
      # reach the published framework fails here rather than in a consumer's CI.
      - run: pnpm lint
      - run: pnpm typecheck
      - run: pnpm test
      - run: pnpm build
`,
)

console.log(`  prepared at .split/${repo}${needsDb ? ' (CI with Postgres)' : ''}`)
if (!push) console.log('  not pushed — build it, then re-run with --push')
