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
FEED_URL="${KERN_FEED_URL:-https://github.com/KernAIO/app/releases/latest/download/releases.json}"

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
# Values are written single-quoted (a password may contain `$`, `#` or a space, and only a
# single-quoted .env value survives that), so strip one enclosing quote of either kind.
env_value() { grep -E "^$1=" .env | head -1 | cut -d= -f2- | sed -e "s/^['\"]//" -e "s/['\"]\$//"; }

# Write a value into .env without going through sed's replacement parsing, where `&`, `|` and `\`
# are syntax. Same helper as install.sh's, for the same reason.
set_env() { # set_env <KEY> <literal value>
  local tmp
  tmp="$(mktemp)" || fail "Could not create a temporary file."
  K="$1" V="$2" awk '
    BEGIN { key = ENVIRON["K"]; val = ENVIRON["V"]; done = 0 }
    !done && index($0, key "=") == 1 { print key "=" q val q; done = 1; next }
    { print }
    END { if (!done) print key "=" q val q }
  ' q="'" .env > "$tmp" && mv "$tmp" .env
}

# Ask a running service what version it is actually on. The images are node:24-slim — no wget, no
# curl — and every service listens on IPv4 only, so `localhost` resolves to ::1 and is refused.
# `node -e fetch(127.0.0.1)` is the shape the Dockerfile HEALTHCHECK uses and the only one that works.
reported_version() { # reported_version <service> <port>
  compose exec -T "$1" node -e "
    fetch('http://127.0.0.1:$2/api/health')
      .then(r => r.json()).then(j => console.log(j.version)).catch(() => console.log(''))
  " 2>/dev/null | tr -d '[:space:]'
}

wait_ready() { # wait_ready <service> <port> <attempts, 2s apart>
  local _attempt
  for _attempt in $(seq 1 "$3"); do
    if compose exec -T "$1" node -e "
      fetch('http://127.0.0.1:$2/api/ready')
        .then(r => process.exit(r.ok ? 0 : 1)).catch(() => process.exit(1))
    " >/dev/null 2>&1; then return 0; fi
    sleep 2
  done
  return 1
}

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

step "Pulling $TARGET"
# Before the dry run, because the dry run has to execute the *target* image to say anything about
# the target release, and before the snapshot, so a pull that fails costs nothing.
#
# KERN_VERSION goes in the environment rather than in `-e`: `-e` sets a variable inside the
# container, which does not change the image tag Compose interpolated from .env — so the dry run
# used to run the OLD image and report on the release the instance was already on. A shell variable
# takes precedence over .env when Compose interpolates `${KERN_VERSION}`, which is what actually
# selects the image.
KERN_VERSION="$TARGET" compose pull || fail "Could not pull the $TARGET images. Nothing has been changed."

step "Checking what the migrations would do"
KERN_VERSION="$TARGET" compose run --rm --no-deps core node dist/migrate.js --check \
  || fail "The migration dry run failed. Nothing has been changed."
# What that dry run covers: core's own schema and every module core hosts. It does not cover chat,
# mail or collab, which own module schemas and migrate them inside their own boot — there is no
# migrate entrypoint in those images to ask. The upgrade compensates by keeping maintenance mode on
# until those services are up and past their migrations, rather than by pretending to know first.
info "covers core and the modules core hosts; chat, mail and collab migrate at boot, under maintenance"

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

# What rollback re-pins. `latest` is not a version you can go back to — it is a moving pointer, and
# after this upgrade it points at TARGET, so recording it would make kern-rollback.sh a no-op that
# reports success. An instance installed before install.sh started pinning is on `latest`, so ask
# the running core what it actually is: the number is baked into the image, so it cannot be wrong.
FROM="$CURRENT"
if [ "$CURRENT" = "latest" ] || [ "$CURRENT" = "main" ]; then
  RESOLVED="$(reported_version core 4000)"
  if [ -n "$RESOLVED" ]; then
    FROM="$RESOLVED"
    info "KERN_VERSION was \"$CURRENT\"; core reports $RESOLVED, so that is what rollback will use"
  else
    info "KERN_VERSION is \"$CURRENT\" and core could not be asked what it is running."
    info "A rollback from this snapshot will refuse; pin KERN_VERSION to a number to fix that."
  fi
fi
printf '%s\n' "$FROM" > "$SNAP/from-version"

# Object storage is NOT in this snapshot: it holds the database, .env and the compose files, and
# nothing else. A file uploaded after it was taken still exists after a rollback, but a rollback
# with --database restores rows that no longer know about it — and rows deleted since will point at
# objects that were already removed. ./kern-backup.sh is the one that mirrors the bucket.
printf 'database, .env, docker-compose.yml, Caddyfile. NOT object storage.\n' > "$SNAP/contents"
info "snapshot: $SNAP (database and configuration only — not object storage)"

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
KERN_VERSION="$TARGET" compose run --rm --no-deps core node dist/migrate.js --maintenance on \
  || undo "Could not turn maintenance mode on."

step "Pinning $TARGET"
set_env KERN_VERSION "$TARGET"

step "Migrating"
compose run --rm --no-deps core node dist/migrate.js || undo "The migrations failed."

step "Starting core"
compose up -d core core-worker || undo "core did not start."
wait_ready core 4000 60 || undo "core did not become ready."
info "core is ready"

# Everything else comes up while maintenance is still on, on purpose. chat, mail and collab each own
# module schemas and migrate them inside their own boot, so turning maintenance off before they had
# started — which is what used to happen here — ran their schema changes with the API already open
# to users. They are the migrations the dry run above cannot see, so they are the ones that most
# need the door shut.
step "Starting everything else"
compose up -d || undo "Not every service started."

step "Waiting for the services that migrate at boot"
for pair in "chat 4100" "mail 4200" "collab 4300"; do
  # deliberate split of "<service> <port>" into $1 and $2
  # shellcheck disable=SC2086
  set -- $pair
  compose ps --status running --quiet "$1" >/dev/null 2>&1 || continue
  wait_ready "$1" "$2" 60 || undo "$1 did not become ready, so its migrations may not have finished."
  info "$1 is ready"
done

step "Opening the API again"
compose run --rm --no-deps core node dist/migrate.js --maintenance off \
  || undo "Could not turn maintenance mode off."

# ---------------------------------------------------------------- verify

step "Checking every service reports $TARGET"
sleep 5
FAILED=""
for pair in "core 4000" "chat 4100" "mail 4200" "collab 4300"; do
  # deliberate split of "<service> <port>" into $1 and $2
  # shellcheck disable=SC2086
  set -- $pair
  compose ps --status running --quiet "$1" >/dev/null 2>&1 || continue
  REPORTED="$(reported_version "$1" "$2")"
  if [ "$REPORTED" = "$TARGET" ]; then info "$1: $REPORTED"; else FAILED="$FAILED $1($REPORTED)"; fi
done

# app is the web front end and has no /api/health to ask — its own healthcheck fetches `/`. So it is
# checked by the image it is running, which is the thing an upgrade actually changes. Skipping it
# entirely, as this loop used to, meant a shell left on the old build passed the upgrade.
if compose ps --status running --quiet app >/dev/null 2>&1; then
  APP_IMAGE="$(compose ps --format '{{.Image}}' app 2>/dev/null | tr -d '[:space:]')"
  case "$APP_IMAGE" in
    *:"$TARGET") info "app: $APP_IMAGE" ;;
    *) FAILED="$FAILED app($APP_IMAGE)" ;;
  esac
fi

[ -z "$FAILED" ] || undo "These services are not on $TARGET:$FAILED"

if [ "$AUTO" = true ]; then
  compose exec -T core node dist/updates-cli.js record "$TARGET" ok >/dev/null 2>&1 || true
  logger -t kern-auto-update "upgraded to $TARGET" 2>/dev/null || true
fi

printf '\n\033[32m✔ Kern is on %s.\033[0m\n' "$TARGET"
printf '  Snapshot kept at %s\n' "$SNAP"
printf '  To go back:      %s/kern-rollback.sh %s\n\n' "$DIR" "$SNAP"
