#!/usr/bin/env bash
# Upgrade a self-hosted Kern instance.
#
#   ./kern-upgrade.sh              upgrade to the newest stable release
#   ./kern-upgrade.sh 1.2.0        upgrade to a specific version
#   ./kern-upgrade.sh --check      run the preflight checks and stop
#   ./kern-upgrade.sh --auto       upgrade only if the instance's own policy says to
#
# `--auto` is what the timer runs. It asks Kern whether it may proceed — the policy, the window and
# the settling period all live in the instance, set by an admin in Admin -> Updates — and does
# nothing at all unless the answer is yes. That way the panel and the job at 03:00 cannot disagree.
#
# Nothing here is clever. It refuses to start when the instance is not in a state to be upgraded,
# takes a snapshot you can go back to, closes the API while migrations run, and checks that every
# service came back on the new version. If any step fails it stops and prints how to undo it.
set -euo pipefail

DIR="${KERN_DIR:-$(cd "$(dirname "$0")" && pwd)}"
cd "$DIR"

SNAPSHOT_DIR="${KERN_SNAPSHOT_DIR:-$DIR/snapshots}"
KEEP_SNAPSHOTS="${KERN_KEEP_SNAPSHOTS:-5}"
FEED_URL="${KERN_FEED_URL:-https://github.com/KernAIO/kern/releases/latest/download/releases.json}"

step()  { printf '\n\033[1m==> %s\033[0m\n' "$1"; }
info()  { printf '    %s\n' "$1"; }
fail()  { printf '\n\033[31m✖ %s\033[0m\n' "$1" >&2; exit 1; }

[ -f .env ] || fail "No .env here. Run this from the directory that holds your docker-compose.yml."
[ -f docker-compose.yml ] || fail "No docker-compose.yml here."
command -v docker >/dev/null || fail "Docker is required."

CHECK_ONLY=false
AUTO=false
TARGET=""
for arg in "$@"; do
  case "$arg" in
    --check) CHECK_ONLY=true ;;
    --auto) AUTO=true ;;
    -*) fail "Unknown option: $arg" ;;
    *) TARGET="$arg" ;;
  esac
done

# --auto runs unattended on a timer, so it says nothing on the ordinary "nothing to do" path.
if [ "$AUTO" = true ]; then
  step() { :; }
  info() { :; }
fi

compose() { docker compose "$@"; }
env_value() { grep -E "^$1=" .env | head -1 | cut -d= -f2- | tr -d '"'; }

CURRENT="$(env_value KERN_VERSION)"
[ -n "$CURRENT" ] || fail "KERN_VERSION is not set in .env."

# ---------------------------------------------------------------- what the instance says

if [ "$AUTO" = true ]; then
  PLAN="$(compose exec -T core node dist/updates-cli.js plan 2>/dev/null | sed -n '/^{/,$p')" \
    || fail "Could not ask Kern whether to upgrade. Is it running?"
  SHOULD="$(printf '%s' "$PLAN" | python3 -c 'import json,sys; print(json.load(sys.stdin)["shouldUpgrade"])' 2>/dev/null || echo False)"
  REASON="$(printf '%s' "$PLAN" | python3 -c 'import json,sys; print(json.load(sys.stdin)["reason"])' 2>/dev/null || echo "unreadable plan")"
  if [ "$SHOULD" != "True" ]; then
    logger -t kern-auto-update "not upgrading: $REASON" 2>/dev/null || true
    exit 0
  fi
  TARGET="$(printf '%s' "$PLAN" | python3 -c 'import json,sys; print(json.load(sys.stdin)["version"])')"
  logger -t kern-auto-update "upgrading to $TARGET" 2>/dev/null || true
fi

# ---------------------------------------------------------------- target version

if [ -z "$TARGET" ]; then
  step "Asking which release is newest"
  if ! command -v curl >/dev/null; then fail "curl is required to look up the newest release."; fi
  # The feed is a signed document; the instance verifies the signature, this only needs the number.
  TARGET="$(curl -fsSL "$FEED_URL" \
    | python3 -c 'import base64,json,sys; d=json.load(sys.stdin); f=json.loads(base64.b64decode(d["payload"])); print(sorted((r["version"] for r in f["releases"] if r["channel"]=="stable"), key=lambda v: [int(p) for p in v.split("-")[0].split(".")])[-1])' \
    2>/dev/null)" || fail "Could not read the release feed at $FEED_URL. Pass a version instead: ./kern-upgrade.sh 1.2.0"
  [ -n "$TARGET" ] || fail "The release feed had no stable release in it."
fi

info "Now:      $CURRENT"
info "Upgrading to: $TARGET"
[ "$CURRENT" != "$TARGET" ] || fail "This instance is already on $TARGET."

# ---------------------------------------------------------------- preflight

step "Preflight"

compose config >/dev/null || fail "docker-compose.yml is not valid. Fix it before upgrading."
info "compose file is valid"

compose ps --status running --quiet postgres >/dev/null 2>&1 || fail "Postgres is not running."
compose exec -T postgres pg_isready -U "$(env_value POSTGRES_USER)" >/dev/null \
  || fail "Postgres is not accepting connections."
info "database is reachable"

DB_BYTES="$(compose exec -T postgres psql -U "$(env_value POSTGRES_USER)" -d "$(env_value POSTGRES_DB)" \
  -tAc "select pg_database_size(current_database())" | tr -d '[:space:]')"
FREE_KB="$(df -Pk "$DIR" | awk 'NR==2 {print $4}')"
NEED_KB="$(( DB_BYTES * 2 / 1024 ))"
[ "$FREE_KB" -gt "$NEED_KB" ] \
  || fail "Not enough disk space for a snapshot: need about $(( NEED_KB / 1024 )) MB, $(( FREE_KB / 1024 )) MB free."
info "disk space is enough for a snapshot"

step "Checking what the migrations would do"
compose run --rm -e "KERN_VERSION=$TARGET" core node dist/migrate.js --check \
  || fail "The migration dry run failed. Nothing has been changed."

if [ "$CHECK_ONLY" = true ]; then
  printf '\n\033[32m✔ Preflight passed. Nothing was changed.\033[0m\n'
  exit 0
fi

# ---------------------------------------------------------------- snapshot

step "Taking a snapshot before anything changes"
STAMP="$(date +%Y%m%d-%H%M%S)"
SNAP="$SNAPSHOT_DIR/$CURRENT-to-$TARGET-$STAMP"
mkdir -p "$SNAP"
compose exec -T postgres pg_dump -U "$(env_value POSTGRES_USER)" -Fc "$(env_value POSTGRES_DB)" > "$SNAP/database.dump" \
  || fail "The database dump failed. Nothing has been changed."
cp .env "$SNAP/.env"
cp docker-compose.yml "$SNAP/docker-compose.yml"
[ -f Caddyfile ] && cp Caddyfile "$SNAP/Caddyfile"
printf '%s\n' "$CURRENT" > "$SNAP/from-version"
info "snapshot: $SNAP"

# keep the last few and no more, so snapshots cannot fill the disk on their own
if [ -d "$SNAPSHOT_DIR" ]; then
  ls -1dt "$SNAPSHOT_DIR"/*/ 2>/dev/null | tail -n +"$(( KEEP_SNAPSHOTS + 1 ))" | xargs -r rm -rf
fi

undo() {
  if [ "$AUTO" = true ]; then
    # Tell the instance it failed. The next run reads this and stands down until an admin has
    # looked — a nightly job that keeps retrying the release that broke turns one bad night into
    # a week of them.
    compose exec -T core node dist/updates-cli.js record "$TARGET" failed "$1" >/dev/null 2>&1 || true
    logger -t kern-auto-update "upgrade to $TARGET failed: $1" 2>/dev/null || true
  fi
  printf '\n\033[31m✖ %s\033[0m\n' "$1" >&2
  printf '\nTo go back to %s:\n\n' "$CURRENT" >&2
  printf '  %s/kern-rollback.sh %s\n\n' "$DIR" "$SNAP" >&2
  exit 1
}

# ---------------------------------------------------------------- apply

step "Closing the API while the database changes"
compose run --rm -e "KERN_VERSION=$TARGET" core node dist/migrate.js --maintenance on \
  || undo "Could not turn maintenance mode on."

step "Pulling $TARGET"
sed -i.bak "s|^KERN_VERSION=.*|KERN_VERSION=$TARGET|" .env && rm -f .env.bak
compose pull || undo "Could not pull the $TARGET images."

step "Migrating"
compose run --rm core node dist/migrate.js || undo "The migrations failed."

step "Starting core"
compose up -d core core-worker || undo "core did not start."
for i in $(seq 1 60); do
  if compose exec -T core wget -qO- http://localhost:4000/api/ready >/dev/null 2>&1; then break; fi
  [ "$i" -lt 60 ] || undo "core did not become ready."
  sleep 2
done
info "core is ready"

step "Opening the API again"
compose run --rm core node dist/migrate.js --maintenance off || undo "Could not turn maintenance mode off."

step "Starting everything else"
compose up -d || undo "Not every service started."

# ---------------------------------------------------------------- verify

step "Checking every service reports $TARGET"
sleep 5
FAILED=""
for svc in core chat mail collab; do
  compose ps --status running --quiet "$svc" >/dev/null 2>&1 || continue
  REPORTED="$(compose exec -T "$svc" node -e "
    const port = {core:4000, chat:4100, mail:4200, collab:4300}['$svc']
    fetch('http://127.0.0.1:'+port+'/api/health')
      .then(r => r.json()).then(j => console.log(j.version)).catch(() => console.log(''))
  " 2>/dev/null | tr -d '[:space:]')"
  if [ "$REPORTED" = "$TARGET" ]; then info "$svc: $REPORTED"; else FAILED="$FAILED $svc($REPORTED)"; fi
done
[ -z "$FAILED" ] || undo "These services are not on $TARGET:$FAILED"

if [ "$AUTO" = true ]; then
  compose exec -T core node dist/updates-cli.js record "$TARGET" ok >/dev/null 2>&1 || true
  logger -t kern-auto-update "upgraded to $TARGET" 2>/dev/null || true
fi

printf '\n\033[32m✔ Kern is on %s.\033[0m\n' "$TARGET"
printf '  Snapshot kept at %s\n' "$SNAP"
printf '  To go back:      %s/kern-rollback.sh %s\n\n' "$DIR" "$SNAP"
