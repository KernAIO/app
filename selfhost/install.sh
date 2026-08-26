#!/usr/bin/env bash
# Kern self-host installer: creates .env with generated secrets, then starts the stack.
#   curl -fsSL https://raw.githubusercontent.com/KernAIO/app/main/selfhost/install.sh | bash
set -euo pipefail
DIR="${KERN_DIR:-$HOME/kern}"
RAW="https://raw.githubusercontent.com/KernAIO/app/main/selfhost"
mkdir -p "$DIR/postgres-init" && cd "$DIR"
mkdir -p "$DIR/systemd"
for f in docker-compose.yml Caddyfile livekit.yaml .env.example postgres-init/01-extensions.sql \
         kern-upgrade.sh kern-rollback.sh systemd/kern-auto-update.service systemd/kern-auto-update.timer; do
  [ -f "$f" ] || curl -fsSL "$RAW/$f" -o "$f"
done
chmod +x kern-upgrade.sh kern-rollback.sh
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
# The timer only ever asks the instance whether it may upgrade; nothing happens until an admin
# turns automatic updates on in Admin -> Updates. Installing it now saves finding out later that
# the switch in the interface had nothing behind it.
if command -v systemctl >/dev/null && [ -d "$HOME/.config" ]; then
  read -rp "Install the update timer, so Kern can update itself if you switch that on later? [Y/n] " yn
  if [[ ! "$yn" =~ ^[Nn] ]]; then
    mkdir -p "$HOME/.config/systemd/user"
    cp systemd/kern-auto-update.service systemd/kern-auto-update.timer "$HOME/.config/systemd/user/"
    systemctl --user daemon-reload
    systemctl --user enable --now kern-auto-update.timer
    loginctl enable-linger "$USER" >/dev/null 2>&1 || true
    echo "✔ update timer installed (systemctl --user list-timers kern-auto-update)"
  fi
else
  echo "ℹ No systemd here. For automatic updates, run the updater service instead:"
  echo "    docker compose --profile autoupdate up -d"
  echo "  It needs the Docker socket, which gives it control of this host — read the docs first."
fi

docker compose $PROFILES pull
docker compose $PROFILES up -d
echo
echo "🎉 Kern is starting. Open: $(grep ^KERN_BASE_URL .env | cut -d= -f2)"
echo "   Logs:    docker compose logs -f"
echo "   Upgrade: ./kern-upgrade.sh          (snapshots first, then applies)"
echo "   Undo:    ./kern-rollback.sh"
