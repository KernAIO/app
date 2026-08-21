#!/usr/bin/env bash
# Serialises `pnpm install` at the umbrella root (several agents/terminals may run it concurrently).
set -e
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LOCK="$ROOT/.install.lock"
for i in $(seq 1 600); do
  if mkdir "$LOCK" 2>/dev/null; then trap 'rmdir "$LOCK"' EXIT; break; fi
  sleep 2
done
cd "$ROOT" && pnpm install "$@"
