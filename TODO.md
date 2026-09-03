# TODO — to v1.0 on 2026-09-16

The working list behind [ROADMAP.md](ROADMAP.md). One line per thing somebody does; tick it in the
commit that does it, with the date. The roadmap says *why*; this says *what, next*. Issues
[#1–#5](https://github.com/KernAIO/app/issues) carry the same slices for anyone outside.

Written 2026-09-02 against what actually runs. Order inside a section is the order to do it in.

## Every day

- [ ] Read the nightly: `release.yml` green, `rollout.yml` green, and
      `curl -s https://app.kernaio.com/api/health | jq -r .version` equals the newest version in
      `releases/latest/download/releases.json`.
- [ ] `pnpm status` at the umbrella root — land or revert anything another session left
      uncommitted or unpushed. On 2026-09-02: 19 uncommitted files in `shell`, an uncommitted
      client change in `module-tracker`.
- [ ] Any red `main` in any repository is the first job of the day.

## 1. Kern Cloud can take money safely — by 2026-09-07 ([#1](https://github.com/KernAIO/app/issues/1))

Nothing below is code; it is configuration, ops and verification. Today the cloud sends no email,
takes no payment, and has no backup.

- [ ] **Outbound mail.** Set `SMTP_URL` (or a Mailgun/Postmark/SES/Resend relay) on the Coolify app
      and the `mail` service; sign up with a fresh address and receive the verification mail;
      invite somebody and receive the invitation; request a magic link and receive it. No email
      has ever left the instance.
- [ ] **Backups off the host.** Nightly `pg_dump` + MinIO/object-storage mirror to Hetzner S3
      (credentials in `~/.claude/kern-devops/infrastructure.md`), 30-day retention, a systemd
      timer on the host — the same shape as `selfhost/kern-backup.sh`.
- [ ] **Restore drill.** Restore last night's dump into a scratch database on the host, count a
      few tables against production, write the procedure into
      `docs/self-hosting/backups.md` as it was actually run.
- [ ] **Somebody is told when it breaks.** An external HTTP probe on `/api/health` (any uptime
      service, or a cron on a second machine) that emails/pings on failure; a `failure()`
      notification step in `release.yml` and `rollout.yml`; a daily job that compares the cloud
      version with the feed and shouts when they differ for more than 30 minutes.
- [ ] **Stripe live.** Set `STRIPE_SECRET_KEY`, `STRIPE_WEBHOOK_SECRET` and the webhook endpoint in
      Stripe; set `KERN_DEFAULT_PLAN_SLUG`; buy Team with a real card in test mode and then live;
      see the invoice; hit the seat limit and be refused; cancel; see the suspension path
      (`repos/shell/tests/e2e/billing-suspended.spec.ts`, uncommitted, is the test to land).
- [ ] **Entitlements enforced.** For every line in the pricing comparison table — seats, storage,
      SSO, audit retention — find the one place in `core` that checks it and prove it refuses.
      Storage is a workspace total, never per seat.
- [ ] **Legal.** Read `/privacy`, `/terms`, `/subprocessors` once, carefully, against what
      actually runs (Hetzner Nuremberg, Mailgun, Stripe); decide whether Kern Cloud offers a DPA;
      make hello@, support@, security@, privacy@ and sales@ deliver somewhere a person reads.
- [ ] **Host hygiene.** `PasswordAuthentication no` in sshd on 128.140.5.236 (key auth is what
      the rollout uses); set `KERN_CLOUD_PG_CONTAINER` as a repository variable so the rollout
      never has to guess the Postgres container.
- [ ] **Cloud on a firmer deploy.** Decide: keep Coolify (each rollout recreates every container,
      ~40 s of nothing serving) or move app.kernaio.com onto the `selfhost/` shape with
      `kern-upgrade.sh` and the timer. Either is fine for v1.0; write the decision into ADR 0002.

## 2. Every page says only what ships — by 2026-09-05 ([#2](https://github.com/KernAIO/app/issues/2))

- [x] Docs: Recruiting, CRM, Automation, Calls and AI pages open with a *Planned* notice
      (2026-09-02).
- [x] Website: Quire and HR are shipped; the tracker's list names what it does today
      (2026-09-02).
- [x] Website launch checklist: the images are public (2026-09-02).
- [ ] Docs sidebar: move the five planned pages under a *Planned* group, or keep them under
      *Modules* with the notice — decide, and make `modules/docs-drive.md` match.
- [ ] Every repository README agrees with the roadmap (`app`, `shell`, `core`, the seven modules,
      `module-template`, `kernel`, `docs`). `HR` and `Inventory` are shipped, not "beyond scope".
- [ ] `pnpm pricing` on the website imports a clean plan catalogue from app.kernaio.com — run it
      and read the output; silence means clean.
- [ ] The website's home page copy names the modules that exist and no others.

## 3. A self-hoster gets from zero to upgraded and back — by 2026-09-11 ([#3](https://github.com/KernAIO/app/issues/3))

Done by running it on a machine nobody has touched, following only
`docs.kernaio.com/self-hosting`. Every step that needed knowledge not on the page is a docs bug;
every failure is a product bug and gets a CI test where one is possible.

- [ ] Clean Ubuntu 24.04 VM: `curl -fsSL https://get.kernaio.com | bash` → first admin signs in,
      creates a workspace, files an issue, sends a chat message, edits a page.
- [ ] `./kern-upgrade.sh --check` passes; the next nightly arrives; Admin → Updates shows it with
      the module diff.
- [ ] Admin → Updates on `auto` with a window ten minutes ahead; the timer upgrades it; the
      instance reports the new version; the admins get the notification.
- [ ] `./kern-rollback.sh` returns it to the previous version; `--database` restores the dump.
- [ ] `./kern-backup.sh` runs; a restore from its output works on a second VM.
- [ ] Coolify: paste `selfhost/coolify/docker-compose.yml`, deploy, sign in; set `KERN_VERSION`
      and redeploy to upgrade.
- [ ] Fix `get.kernaio.com`'s redirect rule to the canonical `KernAIO/app` URL.
- [ ] `install.sh` and `kern-upgrade.sh` are the only two scripts a self-hoster runs; both are
      shellcheck-clean and tested in `selfhost.yml` — add whatever the VM run found.

## 4. A developer ships a module of their own — by 2026-09-14 ([#4](https://github.com/KernAIO/app/issues/4))

Today a third-party module needs a line in `repos/shell/src/lib/modules/registry.ts` and a line
in `repos/core/src/service.ts` (`featureModules`) — a fork of both. v1.0 makes it a build.

- [ ] `shell` Dockerfile: a `KERN_EXTRA_MODULES="@acme/module-crm@1.2.0 …"` build argument that
      installs the packages and generates the `registerModule` lines.
- [ ] `core` Dockerfile: the same argument, generating `featureModules`.
- [ ] `selfhost/`: a documented way to build the two images with extra modules and pin them in
      `.env` (`KERN_IMAGE_SHELL`, `KERN_IMAGE_CORE` or similar), and the drift check covering it.
- [ ] `docs/developers/module-development.md` rewritten as a procedure: degit the template → run
      tests → run it inside a local Kern (`pnpm dev`) → see the screens → build the images → run
      them on a self-host. Followed end to end by an agent with no other context; every gap fixed.
- [ ] `npx degit KernAIO/module-template` produces a module whose `pnpm test` passes on a clean
      machine with no umbrella around it.
- [ ] Decide `pnpm new-module` vs `npm create kern-module`; the README says one thing.
- [ ] `@kernhq/module-template` and `@kernhq/workflow` are installable from npm without a token.

## 5. It is safe to sell — by 2026-09-16 ([#5](https://github.com/KernAIO/app/issues/5))

- [ ] `@kernhq/testing`'s permission matrix runs in every first-party module (it runs in the
      tracker; copy the pattern).
- [ ] Every module carries an isolation test like
      `repos/module-tracker/src/server/isolation.test.ts` — two cross-tenant leaks in the tracker
      and two in core shipped before those tests existed.
- [ ] Rate limits and security headers checked from outside (`curl -I` on the cloud; a small
      script in `scripts/`), and CSP/frame-ancestors verified in the Caddyfile.
- [ ] `repos/shell/tests/e2e/ux.spec.ts` green on every route in all four renderings, and the
      route list complete.
- [ ] Open findings from the interface and service audits (`.audit/` in this checkout) closed or
      written down as deferred with a reason.
- [ ] `core-worker` reports healthy on the cloud (fix lands with the 2026-09-03 nightly — check).
- [ ] Cut **v1.0.0** by hand: `gh workflow run release.yml --repo KernAIO/app --field bump=major`;
      then re-sign its feed with `schemaChanges` and `minPreviousVersion` set deliberately.

## Release machinery follow-ups (small, any day)

- [ ] A `failure()` notification on `release.yml` and `rollout.yml` (also in slice 1).
- [ ] A module's `!`/`BREAKING CHANGE` changeset should mark the platform feed `breaking`
      rather than defaulting to `additive`; today only a person re-signing does that.
- [ ] `docs/developers/releases-and-migrations.md`: a short "when the nightly is red" runbook —
      read the run, republish the module it names, dispatch again.
- [ ] Renovate: fix its onboarding or remove `renovate.json` from every repository; it has never
      opened a pull request.
- [ ] `repos/shell`'s 19 uncommitted files and `module-tracker`'s client change: whoever owns
      them lands them; if nobody does by 2026-09-04, revert.

## After v1.0

Recruiting and CRM (both start from the workflow engine), Automation, Calendar, Drive, Calls, AI,
the personal mail inbox, email-to-issue, outgoing webhooks — in the order a paying team asks.
