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
      has ever left the instance. **Blocked on a relay credential** (2026-09-04): no Mailgun or
      Postmark account exists anywhere; buying one is the owner's call.
- [x] **Backups off the host.** `kern-cloud-backup.timer` at 01:00 UTC: `pg_dump` plus a mirror of
      the `kernaio` bucket into a versioned `kernaio-backups` bucket on Hetzner, 30-day retention
      (2026-09-03).
- [x] **Restore drill.** Last night's dump restored into a scratch database on the host, 150
      tables matched against production (2026-09-03). The procedure still has to be written into
      `docs/self-hosting/backups.md` as it was run.
- [x] **Somebody is told when it breaks.** The `kern-watch` Cloudflare Worker probes `/api/health`
      every five minutes and mails the owner on down, recovery and version change, and when the
      backup heartbeat is older than 26 h (2026-09-03). `release.yml` and `rollout.yml` open an
      issue labelled `release-failure` when they end red (2026-09-04).
- [ ] **Stripe live.** Set `STRIPE_SECRET_KEY`, `STRIPE_WEBHOOK_SECRET` and the webhook endpoint in
      Stripe; set `KERN_DEFAULT_PLAN_SLUG`; buy Team with a real card in test mode and then live;
      see the invoice; hit the seat limit and be refused; cancel; see the suspension path.
      `billing-suspended.spec.ts` landed and the webhook route ships in `module-billing` 0.5.0
      (2026-09-04). **Blocked on the Stripe keys**, which only the account owner can mint.
- [ ] **Entitlements enforced.** For every line in the pricing comparison table — seats, storage,
      SSO, audit retention — find the one place in `core` that checks it and prove it refuses.
      Storage is a workspace total, never per seat.
- [ ] **Legal.** Read `/privacy`, `/terms`, `/subprocessors` once, carefully, against what
      actually runs (Hetzner Nuremberg, Mailgun, Stripe); decide whether Kern Cloud offers a DPA.
      The five mailboxes forward to the owner through Cloudflare Email Routing (2026-09-03).
- [x] **Host hygiene.** `PasswordAuthentication no` in sshd on 128.140.5.236 (2026-09-03).
      `KERN_CLOUD_PG_CONTAINER` stays unset on purpose: Coolify renames every container on each
      rollout, so `rollout.yml` finds Postgres by its compose label instead.
- [ ] **Cloud on a firmer deploy.** Decide: keep Coolify (each rollout recreates every container,
      ~40 s of nothing serving) or move app.kernaio.com onto the `selfhost/` shape with
      `kern-upgrade.sh` and the timer. Either is fine for v1.0; write the decision into ADR 0002.

## 2. Every page says only what ships — by 2026-09-05 ([#2](https://github.com/KernAIO/app/issues/2))

- [x] Docs: Recruiting, CRM, Automation, Calls and AI pages open with a *Planned* notice
      (2026-09-02).
- [x] Website: Quire and HR are shipped; the tracker's list names what it does today
      (2026-09-02).
- [x] Website launch checklist: the images are public (2026-09-02).
- [x] Docs sidebar: the five planned pages and Drive & Calendar sit under a collapsed *Planned
      modules* group; Tracker, Chat, HR and Mail describe what ships and name what does not;
      Inventory has a page (2026-09-04).
- [x] Every repository README agrees with the roadmap. `app`'s table called HR "not built" and
      warned the images were private; the template README promised `npm create kern-module`
      (2026-09-04). Email-to-issue was claimed in three places and is not built — corrected in
      the roadmap, the README, the docs and the website.
- [ ] `pnpm pricing` on the website: run on 2026-09-04, it refused seven highlights the cloud's
      plan catalogue advertises — storage "per user" on all three plans (the entitlement is a
      workspace total), backups on Team and Business (true since 2026-09-03; the script's rule
      still says otherwise), and support response times nobody measures. **Edit the highlights
      in Admin → Plans**, then relax the backup rule in `website/scripts/gen-pricing.mjs`, then
      run it again; silence means clean.
- [x] The website's home page copy names the modules that exist and no others; Inventory joined
      the module list (2026-09-04).

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

- [x] `shell` Dockerfile: `KERN_EXTRA_MODULES` installs the packages and
      `scripts/extra-modules.mjs` rewrites `src/lib/modules/extra.ts`; verified by building the
      image with `@kernhq/module-template@0.2.9` (2026-09-04).
- [x] `core` Dockerfile: the same argument, rewriting `src/extra-modules.ts`; the built image
      lists `template` among its modules (2026-09-04).
- [x] `selfhost/`: `KERN_IMAGE_SHELL` and `KERN_IMAGE_CORE` in all three stacks and
      `.env.example`; the drift check passes (2026-09-04).
- [x] `docs/developers/module-development.md` rewritten as a procedure (2026-09-04). Step 3 —
      the module linked into a local Kern through the same generator — was run against the
      template in both hosts. **Not yet** followed end to end by an agent with no other context.
- [ ] `npx degit KernAIO/module-template` produces a module whose `pnpm test` passes on a clean
      machine with no umbrella around it.
- [x] `npx degit KernAIO/module-template` is the one way; the README no longer promises
      `npm create kern-module` (2026-09-04).
- [x] `@kernhq/module-template` 0.2.9 and `@kernhq/workflow` 0.1.1 resolve from the public
      registry with no token (2026-09-04).

## 5. It is safe to sell — by 2026-09-16 ([#5](https://github.com/KernAIO/app/issues/5))

- [x] `@kernhq/testing`'s permission matrix runs in every first-party module and in the template
      (2026-09-04).
- [x] Every module carries an isolation test (2026-09-04: chat, quire, mail and billing joined
      tracker, hr and inventory). Doing it found that **`mod_mail` had no row-level security at
      all** and that chat's and mail's migration folders were not replay-safe; all three are
      fixed and guarded. Still deliberately unsecured, each with its reason in the module's test:
      billing's `subscriptions`, `overrides` and `workspace_usage` (instance records the
      entitlement resolver reads outside any workspace), tracker's `intake_tokens` and
      `workspaces` (looked up by a stranger's token and by the scheduler), and in core `files`,
      `invitations`, `mcp_codes`, `mcp_consents` and `mcp_tokens` — those five have explicit
      filters everywhere and are the next thing to put behind a policy.
- [x] Rate limits and security headers checked from outside: `scripts/check-edge.sh`
      (2026-09-04). It found the shell sent no HSTS — Caddy now adds it; the cloud gets it at the
      next rollout.
- [ ] `repos/shell/tests/e2e/ux.spec.ts` green on every route in all four renderings, and the
      route list complete.
- [ ] Open findings from the interface and service audits (`.audit/` in this checkout) closed or
      written down as deferred with a reason.
- [ ] `core-worker` reports healthy on the cloud (fix lands with the 2026-09-03 nightly — check).
- [ ] Cut **v1.0.0** by hand: `gh workflow run release.yml --repo KernAIO/app --field bump=major`;
      then re-sign its feed with `schemaChanges` and `minPreviousVersion` set deliberately.

## Release machinery follow-ups (small, any day)

- [x] A `failure()` notification on `release.yml` and `rollout.yml` (2026-09-04).
- [ ] A module's `!`/`BREAKING CHANGE` changeset should mark the platform feed `breaking`
      rather than defaulting to `additive`; today only a person re-signing does that.
- [x] `docs/developers/releases-and-migrations.md`: *When the nightly is red* (2026-09-04).
- [ ] Renovate: fix its onboarding or remove `renovate.json` from every repository; it has never
      opened a pull request.
- [x] `repos/shell`'s 19 uncommitted files landed as the billing-suspension toast;
      `module-tracker`'s and `module-chat`'s client changes were widget strings looked up under
      the wrong prefix, landed as patches (2026-09-04).

## After v1.0

Recruiting and CRM (both start from the workflow engine), Automation, Calendar, Drive, Calls, AI,
the personal mail inbox, email-to-issue, outgoing webhooks — in the order a paying team asks.
