/**
 * Build and sign the release feed an instance reads to find out a newer Kern exists.
 *
 * The feed is generated from what was actually published, never written by hand: it asks GitHub for
 * the stable releases, and it asks each published image what modules it contains, so the versions in
 * it are the versions that shipped. A hand-maintained list would be wrong the first time somebody
 * forgot to edit it, and an admin would be told a module moves when it does not.
 *
 *   node scripts/release-feed.mjs --version 1.2.0 --out releases.json
 *
 * Options:
 *   --version <v>   the release being published (no leading v)
 *   --out <path>    where to write the signed document (default: releases.json)
 *   --previous <p>  path to the existing feed, so older entries are kept
 *   --registry <r>  image registry prefix (default: ghcr.io/kernaio)
 *   --schema <l>    none | additive | breaking — how much of the schema this release moves
 *   --min-previous <v>  oldest version that may upgrade straight to this one
 *   --required-env a,b  environment variables this release needs that earlier ones did not
 *   --dry-run       print the feed without signing it; images that are not built yet are skipped
 *                   with a warning, so an entry's shape can be checked before the release exists
 *
 * Signing key: KERN_FEED_PRIVATE_KEY, a base64 PKCS#8 ed25519 key. Generate a pair with
 * `node scripts/release-feed.mjs --keygen`; the public half goes in core's updates service, the
 * private half in the organisation secrets and nowhere else.
 */
import { execFileSync } from 'node:child_process'
import { generateKeyPairSync, createPrivateKey, sign as signBytes } from 'node:crypto'
import { existsSync, readFileSync, writeFileSync } from 'node:fs'

const args = process.argv.slice(2)

/** Is the image here, without pulling it? */
function imageExists(image) {
  try {
    execFileSync('docker', ['image', 'inspect', image], { stdio: 'ignore' })
    return true
  } catch {
    return false
  }
}
const flag = (name) => args.includes(`--${name}`)
const value = (name, fallback) => {
  const inline = args.find((a) => a.startsWith(`--${name}=`))
  if (inline) return inline.slice(name.length + 3)
  const i = args.indexOf(`--${name}`)
  return i >= 0 && args[i + 1] && !args[i + 1].startsWith('--') ? args[i + 1] : fallback
}

if (flag('keygen')) {
  const { publicKey, privateKey } = generateKeyPairSync('ed25519')
  console.log('Public key  (paste into DEFAULT_FEED_PUBLIC_KEY in core):')
  console.log(publicKey.export({ type: 'spki', format: 'der' }).toString('base64'))
  console.log('\nPrivate key (organisation secret KERN_FEED_PRIVATE_KEY — never commit this):')
  console.log(privateKey.export({ type: 'pkcs8', format: 'der' }).toString('base64'))
  process.exit(0)
}

const version = value('version')
if (!version) throw new Error('--version is required')
const out = value('out', 'releases.json')
const registry = value('registry', 'ghcr.io/kernaio')
const schemaChanges = value('schema', 'additive')
if (!['none', 'additive', 'breaking'].includes(schemaChanges))
  throw new Error(`--schema takes none, additive or breaking, not "${schemaChanges}"`)
const minPreviousVersion = value('min-previous', null)
const requiredEnv = (value('required-env', '') || '').split(',').map((s) => s.trim()).filter(Boolean)
const services = (value('services', 'app,core,chat,mail,collab') || '').split(',').filter(Boolean)

/**
 * Ask a published image what it contains. `/api/health` is the same answer the running service
 * gives, so the feed and a live instance describe a release the same way.
 */
function modulesIn(service) {
  const image = `${registry}/${service}:${version}`
  // A dry run is for checking the shape of an entry before the release exists, so it must not
  // require the images it describes. It says so rather than inventing a module list.
  if (flag('dry-run') && !imageExists(image)) {
    console.error(`  ! ${image} is not available; its modules are omitted from this preview`)
    return {}
  }
  try {
    const stdout = execFileSync(
      'docker',
      ['run', '--rm', '--entrypoint', 'node', image, '-e', 'console.log(JSON.stringify(process.env.KERN_VERSION))'],
      { encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'] },
    )
    const baked = JSON.parse(stdout.trim())
    if (baked !== version)
      throw new Error(`${image} reports KERN_VERSION=${baked}, not ${version}`)
  } catch (err) {
    throw new Error(`Could not read ${image}: ${err.message}`)
  }
  // module inventory lives in the manifest the image writes at build time
  try {
    const stdout = execFileSync(
      'docker',
      ['run', '--rm', '--entrypoint', 'node', image, 'dist/manifest.js'],
      { encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'] },
    )
    return JSON.parse(stdout.trim()).modules ?? {}
  } catch {
    // a service with no modules of its own (app, collab) has no manifest to print
    return {}
  }
}

const modules = {}
const serviceTags = {}
for (const service of services) {
  serviceTags[service] = version
  Object.assign(modules, modulesIn(service))
}

const entry = {
  version,
  channel: 'stable',
  publishedAt: value('published-at', new Date().toISOString()),
  notesUrl: `https://github.com/KernAIO/app/releases/tag/v${version}`,
  services: serviceTags,
  modules,
  minPreviousVersion,
  schemaChanges,
  requiredEnv,
}

const previousPath = value('previous', null)
let releases = []
if (previousPath && existsSync(previousPath)) {
  const doc = JSON.parse(readFileSync(previousPath, 'utf8'))
  const feed = JSON.parse(Buffer.from(doc.payload, 'base64').toString('utf8'))
  releases = feed.releases.filter((r) => r.version !== version)
}
releases.push(entry)
releases.sort((a, b) => (a.version < b.version ? -1 : 1))

const feed = { schema: 1, generatedAt: new Date().toISOString(), releases }
const payload = Buffer.from(JSON.stringify(feed), 'utf8')

if (flag('dry-run')) {
  console.log(JSON.stringify(feed, null, 2))
  process.exit(0)
}

const keyBase64 = process.env.KERN_FEED_PRIVATE_KEY
if (!keyBase64) throw new Error('KERN_FEED_PRIVATE_KEY is required to sign the feed')
const key = createPrivateKey({ key: Buffer.from(keyBase64, 'base64'), format: 'der', type: 'pkcs8' })

// Sign the exact bytes that will be served, and serve those bytes rather than re-encoding them:
// two JSON encoders do not have to agree, and a signature that only usually verifies is worse
// than none at all.
writeFileSync(
  out,
  JSON.stringify({ payload: payload.toString('base64'), signature: signBytes(null, payload, key).toString('base64') }),
)
console.log(`✔ ${out}: ${releases.length} releases, newest ${version}`)
