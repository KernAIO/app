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

### Docs
Documents several people edit at the same time, in nested spaces, with version history and comments.
Published on the collaboration service that already exists.

### Mail
Outbound email per workspace through SMTP, Mailgun, SES, Postmark or Resend, with templates, a
delivery log, bounce handling and suppression. Intake addresses that turn a reply into an issue.

### Self-host
One command installs it. A single domain behind Caddy with automatic HTTPS. Documented upgrade and
backup. Public container images.

## Deferred to v1.1

Cut from v1.0 on 2026-08-22, in order to finish the above rather than start these:

**Drive** · **Calendar** · **HR** (employees, org chart, leave, onboarding) · **Recruiting**
(vacancies, pipeline, interviews, career page) · **CRM** (contacts, companies, deals) ·
**Automation** rules engine and visual builder · **Calls** (LiveKit) · **AI assistant** ·
**Personal mail inbox** (your own IMAP account inside Kern) · **Outgoing webhooks** ·
**Importers** (Jira, Linear, CSV)

The workflow state machine that HR leave and recruiting pipelines would use is already built and in
use by the tracker, so those modules start from a foundation rather than from nothing.

## v1.x and beyond

Cross-workspace shared channels · Meilisearch provider · SCIM · GitHub/GitLab links · CalDAV and
Google Calendar sync · WebDAV · virtual office and call recording · whiteboards · mobile apps
(Capacitor) and desktop (Tauri) · a marketplace for community modules.

## How v1.0 gets finished

Six slices, in this order. Each is finished when somebody can do the thing end to end, not when the
code type-checks.

1. **Every tracker capability is reachable.** The tracker's server offers 137 procedures; the
   interface reaches about a quarter of them. Components, versions, saved views, triage, intake,
   reports, time tracking and imports have no screens at all. This is the largest amount of finished
   work in the project delivering nothing, and it comes first.
2. **A conversation about an issue.** An issue has its own channel; a message becomes an issue and
   links back. Both modules exist — this is the seam that makes "one application" true rather than
   two applications sharing a sidebar.
3. **A document a team writes together.** The collaboration service is built, tested, and has no
   consumer. Spaces, pages, an editor, version history, publishing.
4. **Anyone can install it.** The images are public, the one-command install works on a clean
   machine, and the documentation site is live.
5. **It works in four languages.** Arabic and German are at 155 of 611 strings. Right-to-left
   verified on every screen, not only the ones we remembered.
6. **It is safe to run.** A security review, the outstanding findings from the interface and service
   audits, and a permission matrix that is tested rather than assumed.
