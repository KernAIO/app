#!/usr/bin/env bash
# Kern self-host installer: creates .env with generated secrets, then starts the stack.
#
#   curl -fsSL https://raw.githubusercontent.com/KernAIO/app/main/selfhost/install.sh -o install.sh
#   bash install.sh
#
# Download it and run it, rather than piping it into bash. Piping makes the script its own standard
# input, so every question below would be answered with a line of the script instead of by you. The
# prompts read from /dev/tty for that reason, and the script stops with instructions if there is no
# terminal to read from.
set -euo pipefail

DIR="${KERN_DIR:-$HOME/kern}"
RAW="https://raw.githubusercontent.com/KernAIO/app/main/selfhost"
FEED_URL="${KERN_FEED_URL:-https://github.com/KernAIO/app/releases/latest/download/releases.json}"

fail() { printf '\n\033[31m✖ %s\033[0m\n' "$1" >&2; exit 1; }

# ---------------------------------------------------------------- the terminal

# `read` without this takes the next line of the script when the script is on stdin.
#
# The braces matter: `exec 3</dev/tty 2>/dev/null` opens fd 3 before it applies the 2>, so bash
# still prints its own "Device not configured" first. Redirecting the group suppresses that, and a
# brace group is not a subshell, so fd 3 stays open for the rest of the script.
if [ -e /dev/tty ] && { exec 3</dev/tty; } 2>/dev/null; then
  :
else
  cat >&2 <<'EOS'

✖ This installer asks a few questions and there is no terminal to ask on.

  If you piped this script into bash, the script itself is the standard input, so every answer
  would be read from the script's own text rather than from you. Download it and run it:

      curl -fsSL https://raw.githubusercontent.com/KernAIO/app/main/selfhost/install.sh -o install.sh
      bash install.sh

EOS
  exit 1
fi

ask() { # ask <prompt> <varname>
  local __val
  printf '%s' "$1" >&2
  IFS= read -r __val <&3 || fail "No answer (the terminal closed). Nothing has been changed."
  printf -v "$2" '%s' "$__val"
}

ask_secret() { # ask_secret <prompt> <varname>
  local __val
  printf '%s' "$1" >&2
  stty -echo <&3 2>/dev/null || true
  IFS= read -r __val <&3 || { stty echo <&3 2>/dev/null || true; fail "No answer. Nothing has been changed."; }
  stty echo <&3 2>/dev/null || true
  printf '\n' >&2
  printf -v "$2" '%s' "$__val"
}

yes_no() { # yes_no <prompt> <default y|n>  -> exit status
  local ans
  ask "$1" ans
  [ -n "$ans" ] || ans="$2"
  [[ "$ans" =~ ^[Yy] ]]
}

# ---------------------------------------------------------------- .env writing

# Values go in single-quoted. Docker Compose reads a single-quoted .env value literally — no
# interpolation, no comment stripping — which is the only form that survives a password containing
# `$`, `"`, `&`, `|`, `#` or a space. Unquoted, `pass$word #1` reaches the container as `pass`.
#
# The value never passes through a sed replacement, which is what used to corrupt .env here: sed
# reads `|`, `&` and `\` in the replacement text as syntax, so those passwords either broke the
# file or silently changed. awk gets both strings through the environment, where nothing rewrites
# them, and prints the value with no escape processing at all.
set_env() { # set_env <KEY> <literal value>
  local tmp
  tmp="$(mktemp)" || fail "Could not create a temporary file."
  K="$1" V="$2" awk '
    BEGIN { key = ENVIRON["K"]; val = ENVIRON["V"]; done = 0 }
    !done && index($0, key "=") == 1 { print key "=" q val q; done = 1; next }
    { print }
    END { if (!done) print key "=" q val q }
  ' q="'" "$DIR/.env" > "$tmp" && mv "$tmp" "$DIR/.env"
}

# A single quote cannot be represented inside a single-quoted .env value — the parser stops at the
# first one and there is no escape for it — so it is the one character we have to refuse.
has_quote() { case "$1" in *\'*) return 0 ;; *) return 1 ;; esac; }

# Read a key's value out of .env, with one enclosing quote of either kind stripped. `set_env` writes
# values single-quoted, but a hand-written .env is just as likely to be unquoted or double-quoted, so
# a backfill guard has to read the value rather than pattern-match the line it is written on.
env_value() { # env_value <KEY>
  grep -E "^$1=" "$DIR/.env" | head -1 | cut -d= -f2- | sed -e "s/^['\"]//" -e "s/['\"]\$//"
}

# Is this key present AND non-empty? Every backfill below asks this, and it is the only question that
# is right. The two shapes it replaces were both wrong in their own direction:
#
#   grep -q "^KEY='.\+'"   matched only a SINGLE-QUOTED value, so a hand-written `KEY=abc` looked
#                          unset and the key was appended a second time. Compose reads the last
#                          assignment, so the instance quietly swapped to a freshly generated secret
#                          — a new MAIL_WEBHOOK_TOKEN silently invalidates the provider webhook URL
#                          the operator already registered.
#   grep -q "^KEY="        matched a present-but-blank `KEY=` too, so the backfill it guards never
#                          ran. `.env.example` ships KERN_DIR blank, so that is the normal state of
#                          every instance, and KERN_DIR was therefore never filled in.
env_is_set() { # env_is_set <KEY>
  [ -n "$(env_value "$1")" ]
}

gen() { openssl rand -hex 32; }

# ---------------------------------------------------------------- files

mkdir -p "$DIR/postgres-init" "$DIR/systemd" && cd "$DIR"
for f in docker-compose.yml Caddyfile livekit.yaml .env.example postgres-init/01-extensions.sql \
         kern-upgrade.sh kern-rollback.sh kern-backup.sh \
         systemd/kern-auto-update.service systemd/kern-auto-update.timer \
         systemd/kern-backup.service systemd/kern-backup.timer; do
  [ -f "$f" ] || curl -fsSL "$RAW/$f" -o "$f" || fail "Could not download $f."
done
chmod +x kern-upgrade.sh kern-rollback.sh kern-backup.sh
command -v docker >/dev/null || fail "Docker is required: https://docs.docker.com/get-docker/"
command -v openssl >/dev/null || fail "openssl is required to generate secrets."

# ---------------------------------------------------------------- version

# Never `latest`. A rollback records the version it came from, so an instance on `latest` snapshots
# `from-version: latest` and rolling back re-pins the release it just moved to — a no-op that
# reports success. `latest` also lets a pull landing mid-release give five services five different
# builds, which is the drift docs/adr/0002 exists to prevent.
if [ -n "${KERN_VERSION:-}" ]; then
  VERSION="$KERN_VERSION"
else
  echo "==> Asking which release is newest"
  VERSION="$(curl -fsSL "$FEED_URL" 2>/dev/null \
    | python3 -c 'import base64,json,sys; d=json.load(sys.stdin); f=json.loads(base64.b64decode(d["payload"])); print(sorted((r["version"] for r in f["releases"] if r["channel"]=="stable"), key=lambda v: [int(p) for p in v.split("-")[0].split(".")])[-1])' \
    2>/dev/null)" || VERSION=""
fi
if [ -z "$VERSION" ]; then
  cat >&2 <<EOS

✖ Could not work out which release is newest, and this installer will not pin \`latest\`:
  rollback records the version you came from, and "latest" is not one.

  Pick a version from https://github.com/KernAIO/app/releases and run:

      KERN_VERSION=1.2.0 bash install.sh

EOS
  exit 1
fi
echo "    installing Kern $VERSION"

# ---------------------------------------------------------------- .env

if [ ! -f .env ]; then
  cp .env.example .env

  ask "Domain or IP for Kern (e.g. kern.example.com or 192.168.1.10): " DOMAIN
  [ -n "$DOMAIN" ] || fail "A domain or IP is required."

  while :; do
    ask "Admin email (for Let's Encrypt + first admin): " EMAIL
    case "$EMAIL" in
      ?*@?*.?*) break ;;
      *) echo "   That does not look like an email address. This account becomes an instance" >&2
         echo "   administrator and is the only way back in, so it has to be one you can read." >&2 ;;
    esac
  done

  while :; do
    ask_secret "Admin password: " PASS
    if [ -z "$PASS" ]; then
      echo "   A password is required." >&2
    elif has_quote "$PASS"; then
      echo "   A single quote cannot be stored in .env. Please choose a password without one." >&2
    else
      break
    fi
  done

  PROTO=https
  ACME="$EMAIL"
  # An IP address or `localhost` can never get a public certificate, so Caddy issues its own. The
  # browser will warn once; that is expected on a LAN install.
  if [[ "$DOMAIN" =~ ^[0-9.]+$ || "$DOMAIN" =~ ^\[?[0-9a-fA-F:]+\]?$ || "$DOMAIN" == "localhost" ]]; then
    ACME="internal"
    echo "   $DOMAIN has no public certificate, so Kern will use a self-signed one." >&2
  fi

  set_env KERN_DOMAIN           "$DOMAIN"
  set_env KERN_BASE_URL         "$PROTO://$DOMAIN"
  set_env ACME_EMAIL            "$ACME"
  set_env KERN_VERSION          "$VERSION"
  set_env KERN_DIR              "$DIR"
  # The bare origin, with no path. Presigned URLs are SigV4 signatures over the canonical path, and
  # Caddy routes /<bucket>/* to MinIO without stripping anything, so the path MinIO receives is the
  # path core signed. The `/s3` prefix this used to write made every upload and download 403.
  set_env S3_PUBLIC_ENDPOINT    "$PROTO://$DOMAIN"
  set_env KERN_SECRET           "$(gen)"
  set_env BETTER_AUTH_SECRET    "$(gen)"
  set_env POSTGRES_PASSWORD     "$(gen)"
  set_env KERN_DB_APP_PASSWORD  "$(gen)"
  set_env S3_SECRET_KEY         "$(gen)"
  set_env LIVEKIT_API_KEY       "kern$(openssl rand -hex 4)"
  set_env LIVEKIT_API_SECRET    "$(gen)"
  # The secret a provider's bounce and complaint webhooks must present. Generated rather than left
  # to the operator because the endpoint is reachable from the internet: without a token, anyone can
  # post a forged bounce and permanently suppress any address on the instance.
  set_env MAIL_WEBHOOK_TOKEN    "$(gen)"
  set_env KERN_ADMIN_EMAIL      "$EMAIL"
  set_env KERN_ADMIN_PASSWORD   "$PASS"
  set_env MAIL_FROM             "Kern <no-reply@$DOMAIN>"
  chmod 600 .env
  echo "✔ .env created"
else
  # An existing instance: fill in anything this version of the installer added, and leave the rest.
  # Every guard here asks `env_is_set`, which is true only for a key that is present with a non-empty
  # value — quoted or not. Backfilling is not free: each of these appends a *second* assignment when
  # it misreads, and Compose takes the last one, so a guard that under-reports silently rotates a
  # live secret.
  env_is_set KERN_DIR || set_env KERN_DIR "$DIR"
  if ! env_is_set KERN_DB_APP_PASSWORD; then
    set_env KERN_DB_APP_PASSWORD "$(gen)"
    echo "✔ generated KERN_DB_APP_PASSWORD (the services stop connecting as the database superuser)"
  fi
  # An instance from before the mail webhooks required a token has none, and an empty one makes mail
  # refuse every webhook. Fill it in rather than leave bounce handling quietly switched off.
  if ! env_is_set MAIL_WEBHOOK_TOKEN; then
    set_env MAIL_WEBHOOK_TOKEN "$(gen)"
    echo "✔ generated MAIL_WEBHOOK_TOKEN (mail webhooks now need one; re-point your provider at it)"
  fi
  echo "✔ .env already exists — kept, with anything this version added filled in"
fi

# ---------------------------------------------------------------- optional services

PROFILES=""
yes_no "Enable video calls (LiveKit)? [y/N] " n && PROFILES="$PROFILES --profile calls"
yes_no "Enable office/PDF previews (Gotenberg)? [y/N] " n && PROFILES="$PROFILES --profile preview"

# ---------------------------------------------------------------- timers

if command -v systemctl >/dev/null && [ -d "$HOME/.config" ]; then
  mkdir -p "$HOME/.config/systemd/user"

  # The update timer only ever asks the instance whether it may upgrade; nothing happens until an
  # admin turns automatic updates on in Admin -> Updates. Installing it now saves finding out later
  # that the switch in the interface had nothing behind it.
  if yes_no "Install the update timer, so Kern can update itself if you switch that on later? [Y/n] " y; then
    cp systemd/kern-auto-update.service systemd/kern-auto-update.timer "$HOME/.config/systemd/user/"
    systemctl --user daemon-reload
    systemctl --user enable --now kern-auto-update.timer
    loginctl enable-linger "$USER" >/dev/null 2>&1 || true
    echo "✔ update timer installed (systemctl --user list-timers kern-auto-update)"
  fi

  if yes_no "Install the nightly backup timer (database, files, and this configuration)? [Y/n] " y; then
    cp systemd/kern-backup.service systemd/kern-backup.timer "$HOME/.config/systemd/user/"
    systemctl --user daemon-reload
    systemctl --user enable --now kern-backup.timer
    loginctl enable-linger "$USER" >/dev/null 2>&1 || true
    echo "✔ backup timer installed (backups in $DIR/backups; ./kern-backup.sh runs one now)"
  fi
else
  echo "ℹ No systemd here."
  echo "  Backups:          run ./kern-backup.sh from cron."
  echo "  Automatic updates: docker compose --profile autoupdate up -d"
  echo "  The updater needs the Docker socket, which gives it control of this host — read the docs first."
fi

# ---------------------------------------------------------------- start

# $PROFILES has to word-split: it holds "--profile calls --profile preview" as separate arguments.
# shellcheck disable=SC2086
docker compose $PROFILES pull
# shellcheck disable=SC2086
docker compose $PROFILES up -d

echo
echo "🎉 Kern $VERSION is starting. Open: $(grep '^KERN_BASE_URL=' .env | cut -d= -f2- | tr -d "'")"
echo "   Logs:    docker compose logs -f"
echo "   Backup:  ./kern-backup.sh                (database + files + this configuration)"
echo "   Upgrade: ./kern-upgrade.sh               (snapshots first, then applies)"
echo "   Undo:    ./kern-rollback.sh"
