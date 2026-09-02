# Kern roadmap

> Status: **public, pre-1.0.** The repositories are open and every commit is visible. Target for
> v1.0 is Q4 2026.

## What v1.0 delivers

v1.0 is deliberately narrower than the original plan. Kern is one application for a team's work, and
v1.0 delivers that claim for **issues, conversations and documents**, on a platform that is finished
rather than a wider set that is half-finished.

The rule we cut by: a module ships when every capability its server offers is reachable from the
interface. A module whose API exists and whose screens do not is not in v1.0.

### Platform
Accounts and sessions, sign-in with a password, a link, or an identity provider. Many workspaces per
instance, with membership, built-in and custom roles, groups, and per-object permission bindings.
One notification inbox that spans **every workspace you belong to**. Files, search across modules,
the audit log, workspace settings, and per-workspace module enable/disable. A public REST API with
an OpenAPI document. Installable as an app, in English, German, Persian and Arabic, left-to-right
and right-to-left, light and dark.

### Tracker
Projects, work item types and hierarchy, custom fields, and workflows with conditions, validators
and post-functions. Issues with rich descriptions, relations, comments, watchers and attachments.
List and board views, the KQL query language and saved views. Cycles, milestones, versions,
components and labels. Triage and intake, including issues raised by email. Time tracking with
worklogs. Reports: burndown, velocity and created-versus-resolved.

### Chat
Channels, private channels, group and direct messages. Threads, reactions, mentions that notify,
pinned messages, read state and unread counts, presence and typing. Search. Voice and video
messages, and file attachments. **Object channels** — a conversation attached to an issue, and a
message that becomes one.

### Quire
Documents several people edit at the same time, in nested spaces, with version history and comments.
Published on the collaboration service that already exists. A *page* has a published version and a
draft, so a documentation site never shows half-written text; a *live doc* is always live. Spaces,
the page tree, the editor, version history and draft/publish are built; published sites are
addressed by path. See [ADR 0006](docs/adr/0006-collaborative-documents.md).

### Mail
Outbound email per workspace through SMTP, Mailgun, SES, Postmark or Resend, with templates, a
delivery log, bounce handling and suppression. Intake addresses that turn a reply into an issue.

### Self-host
One command installs it. A single domain behind Caddy with automatic HTTPS. Documented upgrade and
backup. Public container images.

## Deferred to v1.1

Cut from v1.0 on 2026-08-22, in order to finish the above rather than start these:

**Drive** · **Calendar** · **HR** (only onboarding remains — directory, org chart, offices, leave,
attendance and approvals are built, see below) · **Recruiting**
(vacancies, pipeline, interviews, career page) · **CRM** (contacts, companies, deals) ·
**Automation** rules engine and visual builder · **Calls** (LiveKit) · **AI assistant** ·
**Personal mail inbox** (your own IMAP account inside Kern) · **Outgoing webhooks** ·
**Importers** (Jira, Linear, CSV)

The workflow state machine that HR leave and recruiting pipelines would use is already built and in
use by the tracker, so those modules start from a foundation rather than from nothing.

## Built beyond the v1.0 scope

Three first-party modules are built, published on npm and registered in the shell, but stand
outside the v1.0 finish line on purpose — they ride the shared platform (kernel, i18n, releases)
without the v1.0 bar that every server capability be reachable from the interface:

- **HR** (`@kernhq/module-hr`) — a directory of people, an org chart, offices, leave, attendance
  and an approvals inbox, all with working screens. Cut from v1.0 on 2026-08-22 and built anyway;
  onboarding is the part that is still missing.
- **Billing** (`@kernhq/module-billing`) — plans, subscriptions and entitlements. The cloud
  instance's plan catalogue is its data; it is administered from the core admin console (plans and
  subscriptions) and workspace settings rather than a sidebar section.
- **Inventory** (`@kernhq/module-inventory`) — the company's asset register in one view: what it
  owns, who holds each item, purchase and warranty details, and a full history of every change.

## v1.x and beyond

Cross-workspace shared channels · Meilisearch provider · SCIM · GitHub/GitLab links · CalDAV and
Google Calendar sync · WebDAV · virtual office and call recording · whiteboards · mobile apps
(Capacitor) and desktop (Tauri) · a marketplace for community modules.

## How v1.0 gets finished

Six slices, in this order. Each is finished when somebody can do the thing end to end, not when the
code type-checks.

1. **Every tracker capability is reachable.** *Nearly there.* The tracker is customisable end to
   end: a project starts from one of four team templates, an administrator adds a custom field and
   decides where it appears on each work item type, and the issue renders it. Reachable now:
   comments with mentions and attachments, relations, sub-issues, links, approvals, triage,
   grouping by a custom field, `relation` and `formula` fields, saved views, components, versions
   and labels, time tracking, and reports on burndown, velocity, created-versus-resolved and time.
   **Still without screens:** imports, issue templates, recurring issues, the workflow editor, and
   the public intake form — the form's questions are derived from the layout, but the page a
   stranger fills in does not exist yet.

2. **A conversation about an issue.** An issue has its own channel; a message becomes an issue and
   links back. Both modules exist — this is the seam that makes "one application" true rather than
   two applications sharing a sidebar.
3. **A document a team writes together.** The collaboration service had no consumer at all; it now
   has one — `@kernhq/module-quire`, with spaces, a nested page tree and the access check the
   gateway asks for. The editor, version history and publishing are built too: a page has a draft
   and a published version, and a published site is addressed by path.
4. **Anyone can install it.** The images are public, the one-command install works on a clean
   machine, and the documentation site is live.
5. **It works in four languages.** German, Persian, Arabic and Turkish ship alongside English, and
   coverage is measured, not guessed: `app/scripts/i18n-coverage.mjs` counts 3,645 user-facing
   strings across the shell and the modules — inlang plumbing, placeholder-only templates and
   input-format examples excluded, since no locale can translate those — and flags 143 German, 43
   Turkish and 32 each of Arabic and Persian as still identical to English (as of 2026-09-02).
   Every one of those has been audited and is deliberate: brand and product names, words German
   writes the same way, and the module template's English-only starter strings. The last genuinely
   untranslated strings shipped on 2026-09-02, so the translation debt is zero. Right-to-left
   verified on every screen, not only the ones we remembered.
6. **It is safe to run.** A security review, the outstanding findings from the interface and service
   audits, and a permission matrix that is tested rather than assumed.
