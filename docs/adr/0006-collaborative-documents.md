# ADR 0006 — Collaborative documents

- Status: accepted (2026-08-24)
- Context: The `collab` service has existed since the platform was laid out — Hocuspocus and Yjs on
  :4300, routed at `/collab*`, running in Compose, covered by tests — and nothing in Kern has ever
  opened a document in it. Its own README says so. `ROADMAP.md` makes "a document a team writes
  together" slice 3 of v1.0, `docs/PLAN.md:59` specified the module a year ago, and `DESIGN.md` §3.6
  already draws the page. What did not exist was any decision about how prose, structure, drafts and
  permissions divide between the CRDT and the database — so the first module to need it would have
  invented one, and every module after it would have inherited whatever that turned out to be.

  Two things were also wrong with the seam itself. `<module>.collab.access` had never once succeeded:
  the gateway sends `{workspaceId, type, id, userId}` and reads `{canRead, canWrite}`, the only
  implementation declared `{workspaceId, issueId, userId}` returning `{canView, canEdit}`, and the
  fallback for "this module does not answer" is *plain workspace membership* — so the failure was
  invisible and looked exactly like a module that worked. And `kern_collab.documents` was created
  imperatively on boot with no row-level security, the one table in Kern where tenant isolation
  rested entirely on an application check.

## Decision

**1. Prose is Yjs. Everything else is Postgres.**

Only the body text of a page lives in a Y.Doc, named `ws:<workspaceId>:quire:page:<pageId>`. The
tree, spaces, database rows, properties, views, comment metadata and permissions are ordinary rows in
`mod_quire`, mutated over oRPC and broadcast with `kernel.realtime.change()`.

Kern has two independent realtime paths — the collab socket and the `ws:` channel through the chat
gateway — and they stay independent. They look alike (`ws:<workspaceId>:<module>:<id>` against
`ws:<workspaceId>:<module>:<type>:<id>`) and are unrelated; conflating them would put cache
invalidation and CRDT sync on one connection whose failure modes are nothing like each other.

The rule for deciding: if two people editing it at the same time should *merge*, it is Yjs. If the
last write should win and every client should refetch, it is a row.

**2. The title lives in the Y.Doc, and is mirrored to a column.**

A relational `pages.title` alone clobbers under concurrent rename — the commonest thing two people do
to a new page at once. The title is a `Y.Text` in the same document; the column exists so the tree
can be queried and sorted without decoding a CRDT, and is written from the store hook. The document
is the truth, the column is an index.

**3. The Y.Doc is always the draft. `page_versions` is the backbone.**

A version row holds the Yjs state, the ProseMirror JSON, the statically rendered HTML and the
flattened text. Two kinds of page then fall out of one mechanism rather than two:

- a **page** serves `published_version_id` to readers without edit rights and to every public URL;
  `Publish` writes a version and repoints the pointer, and "3 unpublished changes" is the current
  state vector against that version's;
- a **live doc** serves the Y.Doc to everyone, and still accumulates versions, so history and restore
  behave identically.

The consequence worth stating: the **static renderer ships with the editor, not with publishing**.
Draft/publish, public pages, export, PDF and search all read it, so a node the editor can produce and
the renderer cannot draw is a bug on the day it is added, not a year later.

**4. The module is hosted by core, not by collab.**

`defaultHost` accepts `'collab'`, but Hocuspocus owns that service's HTTP listener and serves two
paths from a request hook — there is no Fastify and no oRPC there. Hosting on core means
`/api/quire` is served exactly like `/api/tracker`, with no Caddy change, no new port and no new
process. Collab stays a sync server that owns no domain data and reaches the module over the seam
that already exists.

**5. The shapes that cross that seam are declared once, in `@kernhq/contracts`.**

`CollabAccessInput`, `CollabAccess`, `formatCollabDocument`/`parseCollabDocument`, the
`collab.document.*` procedure shapes and a typed `collab.document.updated` event. The gateway and the
module compile against one definition, because the alternative is what already happened: two
signatures that disagreed, a fallback that hid it, and a permission check that had never run.

`collab.document.{state,apply,snapshot,delete,presence}` exist because the socket is otherwise the
only way to see a document, and a module needs the state for version history, export, restore and
import. `document.apply` goes through a direct connection so a server-side write reaches the people
currently editing instead of being overwritten by their next keystroke.

**6. A page is scoped at `object`, with its ancestors and its space above it.**

The permission engine resolves nearest-scope-first, so authorising a page means handing it the chain
`page → ancestors → space → workspace`. That is what makes "everyone may read the Handbook, the
design team may write it, and this contractor may read one page of it" expressible without a second
permission system, and what makes a restriction on a parent page apply to its children.

`space` has been a `PermissionScopeKind` since before there was anything to bind at it. This is what
it was for.

**7. `kern_collab.documents` is migrated and secured like any tenant table.**

A real migration folder, `workspace_id` + forced row-level security, every read and write inside
`withWorkspace`. `Database.migrateSchema(schema, folder, lockKey?)` was added to the kernel so a
service that owns tables of its own gets migrations for the same reasons a module does.

## Consequences

- A read-only participant is visible in presence but broadcasts no caret. Read-only is decided by the
  gateway and the browser only learns it as a hint, so the stripping happens server-side.
- Undo must be scoped per user (`Y.UndoManager` with `trackedOrigins`). It is not the default, and
  the symptom is ⌘Z undoing a colleague's paragraph.
- Comment anchors use Yjs *relative* positions. Index positions do not survive concurrent edits.
- Nothing removed a document when its object was deleted; purging a page now tells collab to forget
  it, best-effort, because a collab service that is briefly down must not turn a successful delete
  into an error.
- Collab has no Redis/Valkey Hocuspocus extension, so multi-instance still needs a sticky load
  balancer. That is a known gap, separable from this decision, and should close before v1.0.
- **Anything that sorts by a generated key needs `COLLATE "C"`.** `ORDER BY` uses the database
  collation, not code point order, and ours is `en_US.UTF-8` where `'U' < 'c'` is false. This is not
  specific to documents — it applies to the tracker's `rank` too, which currently lacks it.

## Alternatives considered

**Everything in the CRDT, including the tree.** Notion-like, and it makes moving a page merge
cleanly. Rejected: the tree is what every list, search result, breadcrumb and permission check reads,
and none of them should have to load and decode a CRDT to answer "what is in this space". A move is
also the one tree operation where last-write-wins is *correct* — two people dragging the same page to
different places should not produce both.

**Hosting the module on collab.** Tempting, because `quire.collab.access` would then be an in-process
call instead of a NATS round trip. Rejected: it would need an HTTP server, a Caddy route and a second
place that runs migrations, to save a call that happens once per socket rather than once per request.

**A separate `documents` service.** Rejected by the rule in `kern-module`: a module needs its own
process only for a runtime reason. The CRDT is already in one, and the metadata is ordinary CRUD.
