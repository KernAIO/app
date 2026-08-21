#!/usr/bin/env bash
# Kern self-host installer: creates .env with generated secrets, then starts the stack.
#   curl -fsSL https://raw.githubusercontent.com/KernALO/kern/main/selfhost/install.sh | bash
set -euo pipefail
DIR="${KERN_DIR:-$HOME/kern}"
RAW="https://raw.githubusercontent.com/KernALO/kern/main/selfhost"
mkdir -p "$DIR/postgres-init" && cd "$DIR"
for f in docker-compose.yml Caddyfile livekit.yaml .env.example postgres-init/01-extensions.sql; do
  [ -f "$f" ] || curl -fsSL "$RAW/$f" -o "$f"
done
command -v docker >/dev/null || { echo "Docker is required: https://docs.docker.com/get-docker/"; exit 1; }
gen() { openssl rand -hex 32; }
if [ ! -f .env ]; then
  cp .env.example .env
  read -rp "Domain or IP for Kern (e.g. kern.example.com or 192.168.1.10): " DOMAIN
  read -rp "Admin email (for Let's Encrypt + first admin): " EMAIL
  read -rsp "Admin password: " PASS; echo
  PROTO=https; ACME="$EMAIL"
  if [[ "$DOMAIN" =~ ^[0-9.]+$ || "$DOMAIN" == "localhost" ]]; then PROTO=https; ACME="internal"; fi
  sed -i.bak \
    -e "s|^KERN_DOMAIN=.*|KERN_DOMAIN=$DOMAIN|" \
    -e "s|^KERN_BASE_URL=.*|KERN_BASE_URL=$PROTO://$DOMAIN|" \
    -e "s|^ACME_EMAIL=.*|ACME_EMAIL=$ACME|" \
    -e "s|^S3_PUBLIC_ENDPOINT=.*|S3_PUBLIC_ENDPOINT=$PROTO://$DOMAIN/s3|" \
    -e "s|^KERN_SECRET=.*|KERN_SECRET=$(gen)|" \
    -e "s|^BETTER_AUTH_SECRET=.*|BETTER_AUTH_SECRET=$(gen)|" \
    -e "s|^POSTGRES_PASSWORD=.*|POSTGRES_PASSWORD=$(gen)|" \
    -e "s|^S3_SECRET_KEY=.*|S3_SECRET_KEY=$(gen)|" \
    -e "s|^LIVEKIT_API_KEY=.*|LIVEKIT_API_KEY=kern$(openssl rand -hex 4)|" \
    -e "s|^LIVEKIT_API_SECRET=.*|LIVEKIT_API_SECRET=$(gen)|" \
    -e "s|^KERN_ADMIN_EMAIL=.*|KERN_ADMIN_EMAIL=$EMAIL|" \
    -e "s|^KERN_ADMIN_PASSWORD=.*|KERN_ADMIN_PASSWORD=$PASS|" \
    -e "s|^MAIL_FROM=.*|MAIL_FROM=\"Kern <no-reply@$DOMAIN>\"|" .env && rm -f .env.bak
  echo "✔ .env created"
fi
PROFILES=""
read -rp "Enable video calls (LiveKit)? [y/N] " yn; [[ "$yn" =~ ^[Yy] ]] && PROFILES="$PROFILES --profile calls"
read -rp "Enable office/PDF previews (Gotenberg)? [y/N] " yn; [[ "$yn" =~ ^[Yy] ]] && PROFILES="$PROFILES --profile preview"
docker compose $PROFILES pull
docker compose $PROFILES up -d
echo
echo "🎉 Kern is starting. Open: $(grep ^KERN_BASE_URL .env | cut -d= -f2)"
echo "   Logs: docker compose logs -f    Upgrade: docker compose pull && docker compose up -d"
