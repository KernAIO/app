# ADR 0001 — Multi-repo services sharing one module kernel

- Status: accepted (2026-08-21)
- Context: Kern must ship as a set of independently deployable services (owner decision), yet features are authored as plug-and-play modules and a solo developer must stay productive.
- Decision:
  1. Services live in separate repositories under `KernALO` (`app`, `core`, `chat`, `mail`, `collab`); shared code in `kernel` (libs) and `modules` (first-party modules).
  2. Every backend service is an instance of the same runtime (`@kernalo/kernel`) hosting a configured list of modules. Which module runs where is configuration, not code.
  3. Modules own their tables in a dedicated Postgres schema (`mod_<id>`); cross-module access only through contracts (`kernel.call`) and events (NATS JetStream) — in-process when co-hosted, remote otherwise.
  4. `kern` repo acts as the umbrella dev workspace (pnpm links sibling clones) and the self-host distribution.
- Consequences: contracts are versioned and published (GitHub Packages during private phase, npm after release); rule "contracts first, then consumers"; standalone CI per repo consumes published packages.
