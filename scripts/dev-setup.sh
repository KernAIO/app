#!/usr/bin/env bash
# Clones (or updates) every Kern repository into ./repos and installs dependencies.
set -euo pipefail
cd "$(dirname "$0")/.."
ORG="${KERN_ORG:-KernALO}"
REPOS=(app core chat mail collab kernel modules docs)
mkdir -p repos
for r in "${REPOS[@]}"; do
  if [ -d "repos/$r/.git" ]; then
    echo "↻ $r: pulling"; git -C "repos/$r" pull --ff-only || true
  else
    echo "⤓ $r: cloning"; git clone "https://github.com/$ORG/$r.git" "repos/$r"
  fi
done
command -v pnpm >/dev/null || corepack enable
pnpm install
cp -n dev/.env.example .env 2>/dev/null || true
echo
echo "✔ Ready. Next:"
echo "   pnpm infra      # start Postgres/NATS/Valkey/MinIO/Mailpit"
echo "   pnpm db:migrate # run migrations"
echo "   pnpm dev        # start all services with hot reload"
