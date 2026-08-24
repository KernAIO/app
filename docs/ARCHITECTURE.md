# Kern architecture (short)

See `docs/PLAN.md` for the full plan and `docs/adr/` for decisions.

```
                       ┌────────────┐
   browser/PWA ──────▶ │   Caddy    │ ── /            ─▶ app     (SvelteKit, :3000)
                       │ (TLS, L7)  │ ── /api/*       ─▶ core    (Fastify + kernel, :4000)  ─┐
                       │            │ ── /api/chat,/ws─▶ chat    (kernel + WS gateway, :4100)│
                       │            │ ── /api/mail    ─▶ mail    (kernel + IMAP sync, :4200) │ NATS JetStream
                       │            │ ── /collab      ─▶ collab  (Hocuspocus/Yjs, :4300)     │ (events, req/reply, KV)
                       │            │ ── /s3          ─▶ minio                                │
                       └────────────┘                   core-worker (pg-boss jobs) ──────────┘
                                              Postgres 18 (per-module schemas, RLS) · Valkey · MinIO · LiveKit(opt)
```

- **Kernel** (`@kernhq/kernel`): `defineModule()` manifest, module registry, typed event bus (in-proc + NATS), `call()` for cross-module/service requests, authz engine, jobs (pg-boss), settings/secrets, provider interfaces (mail, search, storage, realtime), migrations runner.
- **Contracts** (`@kernhq/contracts`): Zod schemas, oRPC contracts, event payloads, permission keys, error codes — the only thing two modules/services share.
- **Modules** (`@kernhq/module-*`): `/contract`, `/server` (routes, schema, migrations, events, jobs, permissions, capabilities, automations), `/client` (Svelte routes, nav, presenters, slots, i18n). A workspace switches a whole module on or off; a module that different customers want *different amounts* of also declares **capabilities** — named sub-features with dependencies, off for the whole workspace rather than for one person, answering 404 rather than 403. See [ADR 0007](adr/0007-module-capabilities.md).
- **Tenancy**: global `users/workspaces/memberships/notifications`; every tenant table has `workspace_id` + RLS via `SET LOCAL app.workspace_id`.
- **Realtime**: one WS per client to `chat`; server events `{ws, module, entity, id, op}` → TanStack Query invalidation; NATS fan-out across instances.
