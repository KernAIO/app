# Kern roadmap

> Status: pre-release. The repos are private while we build v1.0; everything goes public at launch.

## v1.0 (target: Q4 2026)
- **Platform**: multi-workspace with cross-workspace unified inbox, roles/groups/custom permissions, module system (per-workspace enable), global search, files, audit log, REST API + OpenAPI, webhooks, importers (Jira/Linear/CSV), PWA with push.
- **Tracker**: work item types & hierarchy (Initiative→Epic→Issue→Sub-task), custom fields, workflows with conditions/validators/post-functions & approvals, boards/list/calendar/timeline/spreadsheet views, KQL query language & saved views, cycles, milestones, releases, components, triage & intake (incl. email), time tracking & timesheets, reports (burndown, velocity, CFD).
- **Chat**: channels/DMs/threads, mentions, reactions, read states, pins, object channels (chat on any issue/candidate/deal), presence & typing, slash commands, bots/webhooks.
- **Docs & Drive**: real-time collaborative docs (CRDT), nested spaces, version history, publishing; file drive with share links, previews, versions.
- **HR**: employees & org chart, leave management with approvals, holidays, schedules, onboarding checklists.
- **Recruiting**: vacancies, candidate pipeline, interviews, scorecards, public career page.
- **CRM**: contacts, companies, leads/deals pipelines, activities, email linking.
- **Automation**: trigger → condition → action rules with branches, smart values, schedules, sandboxed scripts.
- **Mail**: per-workspace outbound providers (SMTP/Mailgun/SES/Postmark/Resend); personal IMAP/SMTP inbox linked to issues/candidates/deals; intake addresses.
- **Calls**: LiveKit audio/video, huddles in channels, interview calls.
- **AI (bring your own key)**: summaries, drafting, semantic search, @kern assistant, automation steps.
- **Self-host**: one-command Docker install, single domain behind Caddy, upgrade & backup scripts.

## v1.x (after launch)
Cross-workspace shared channels (Slack-Connect-style) · Meilisearch provider · SCIM · GitHub/GitLab PR links · CalDAV/Google Calendar sync · WebDAV · virtual office & call recording · whiteboards · mobile apps (Capacitor) & desktop (Tauri) · marketplace for community modules.
