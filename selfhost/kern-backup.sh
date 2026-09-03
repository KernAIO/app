#!/usr/bin/env bash
# Back up a self-hosted Kern instance: the database, the object storage, and the configuration
# needed to rebuild the stack around them.
#
#   ./kern-backup.sh                 take a backup, prune old ones
#   ./kern-backup.sh --list          list the backups you have
#   ./kern-backup.sh --keep 30       keep 30 instead of the default 14
#   ./kern-backup.sh --to /mnt/nas   write somewhere other than ./backups
#
# This is not the same thing as an upgrade snapshot. `kern-upgrade.sh` snapshots the database and
# the compose files so a bad release can be undone in a hurry; it does NOT copy object storage,
# because that would make every upgrade wait on the size of the whole bucket. So a
# `kern-rollback.sh --database` can bring back rows that refer to files which are no longer there.
# This script is the one that captures both at the same moment, which is what you restore from when
# the disk fails rather than when a release did.
#
# Restoring is deliberately manual — see RESTORE.txt inside each backup.
set -euo pipefail

SELF="$(cd "$(dirname "$0")" && pwd)/$(basename "$0")"
DIR="${KERN_DIR:-$(cd "$(dirname "$0")" && pwd)}"
cd "$DIR"

BACKUP_DIR="${KERN_BACKUP_DIR:-$DIR/backups}"
KEEP="${KERN_KEEP_BACKUPS:-14}"
LIST_ONLY=false

step() { printf '\n\033[1m==> %s\033[0m\n' "$1"; }
info() { printf '    %s\n' "$1"; }
fail() { printf '\n\033[31m✖ %s\033[0m\n' "$1" >&2; exit 1; }

while [ $# -gt 0 ]; do
  case "$1" in
    # The usage is the comment at the top of this file; print it rather than keep a second copy.
    -h|--help) sed -n '2,/^$/p' "$SELF" | sed 's/^# \{0,1\}//'; exit 0 ;;
    --list) LIST_ONLY=true ;;
    --keep) shift; [ $# -gt 0 ] || fail "--keep needs a number."; KEEP="$1" ;;
    --keep=*) KEEP="${1#--keep=}" ;;
    --to) shift; [ $# -gt 0 ] || fail "--to needs a directory."; BACKUP_DIR="$1" ;;
    --to=*) BACKUP_DIR="${1#--to=}" ;;
    -*) fail "Unknown option: $1" ;;
    *) fail "Unexpected argument: $1" ;;
  esac
  shift
done

case "$KEEP" in ''|*[!0-9]*) fail "--keep takes a number, not \"$KEEP\"." ;; esac

if [ "$LIST_ONLY" = true ]; then
  [ -d "$BACKUP_DIR" ] || fail "No backups in $BACKUP_DIR yet."
  du -sh "$BACKUP_DIR"/*/ 2>/dev/null || fail "No backups in $BACKUP_DIR yet."
  exit 0
fi

[ -f .env ] || fail "No .env here. Run this from the directory that holds your docker-compose.yml."
[ -f docker-compose.yml ] || fail "No docker-compose.yml here."
command -v docker >/dev/null || fail "Docker is required."

compose() { docker compose "$@"; }
# Values are written single-quoted, because a password may contain `$`, `#` or a space and only a
# single-quoted .env value survives that. Strip one enclosing quote of either kind.
env_value() { grep -E "^$1=" .env | head -1 | cut -d= -f2- | sed -e "s/^['\"]//" -e "s/['\"]\$//"; }

compose ps --status running --quiet postgres >/dev/null 2>&1 || fail "Postgres is not running."

STAMP="$(date +%Y%m%d-%H%M%S)"
DEST="$BACKUP_DIR/$STAMP"
mkdir -p "$DEST" || fail "Could not create $DEST."

# A half-written backup that looks finished is worse than none, so the directory is only given its
# real name once every part has been written.
cleanup_failed() { rm -rf "$DEST"; }

# ---------------------------------------------------------------- database

step "Dumping the database"
# -Fc is the custom format: compressed, and pg_restore can be selective on the way back. Taken as
# POSTGRES_USER (the superuser) rather than kern_app, so it includes every object regardless of
# owner and is not filtered by row-level security — a dump taken as kern_app would silently contain
# only the rows its policies let it see, which is the worst possible backup.
if ! compose exec -T postgres pg_dump \
      -U "$(env_value POSTGRES_USER)" -Fc "$(env_value POSTGRES_DB)" > "$DEST/database.dump"; then
  cleanup_failed
  fail "The database dump failed. Nothing was kept."
fi
info "database.dump ($(du -h "$DEST/database.dump" | cut -f1))"

# ---------------------------------------------------------------- object storage

step "Mirroring object storage"
S3_BUCKET="$(env_value S3_BUCKET)"
S3_ACCESS_KEY="$(env_value S3_ACCESS_KEY)"
S3_SECRET_KEY="$(env_value S3_SECRET_KEY)"
S3_ENDPOINT="$(env_value S3_ENDPOINT)"

if compose ps --status running --quiet minio >/dev/null 2>&1; then
  mkdir -p "$DEST/files"
  # `mc mirror` into a mounted directory, run on the compose network so it reaches minio by name.
  # --overwrite --remove makes the copy match the bucket rather than accumulate: without --remove a
  # mirror only ever grows, and a "backup" that can never forget a deleted file is not a copy of
  # anything that existed.
  if compose run --rm --no-deps \
      -v "$DEST/files:/backup" \
      --entrypoint /bin/sh minio-init -c "
        mc alias set src '$S3_ENDPOINT' '$S3_ACCESS_KEY' '$S3_SECRET_KEY' >/dev/null &&
        mc mirror --overwrite --remove --quiet \"src/$S3_BUCKET\" /backup
      "; then
    info "files/ ($(du -sh "$DEST/files" | cut -f1))"
  else
    cleanup_failed
    fail "The object storage mirror failed. Nothing was kept."
  fi
else
  # An instance pointed at an external S3 has nothing local to mirror, and copying somebody else's
  # bucket to this disk is not this script's business. Say so rather than leaving a silent gap.
  printf 'This instance uses external object storage at %s.\nIt is NOT in this backup; back it up where it lives.\n' \
    "$S3_ENDPOINT" > "$DEST/files-EXTERNAL.txt"
  info "object storage is external ($S3_ENDPOINT) — recorded, not copied"
fi

# ---------------------------------------------------------------- configuration

step "Copying the configuration"
cp .env "$DEST/.env"
cp docker-compose.yml "$DEST/docker-compose.yml"
[ -f Caddyfile ] && cp Caddyfile "$DEST/Caddyfile"
[ -f livekit.yaml ] && cp livekit.yaml "$DEST/livekit.yaml"
[ -d postgres-init ] && cp -R postgres-init "$DEST/postgres-init"
# .env holds every secret this instance has, so the backup is exactly as sensitive as .env is.
chmod -R go-rwx "$DEST"
info "configuration copied (.env included — treat this directory as a secret)"

cat > "$DEST/RESTORE.txt" <<EOS
Kern backup $STAMP
Version at the time: $(env_value KERN_VERSION)

Contents
  database.dump   pg_dump -Fc of the whole database
  files/          a mirror of the object storage bucket "$S3_BUCKET"
  .env            every secret this instance has. Keep this directory private.
  docker-compose.yml, Caddyfile, livekit.yaml, postgres-init/

To restore onto an empty host

1. Install Docker, then put this directory's .env, docker-compose.yml, Caddyfile and
   livekit.yaml into a new directory, and download the scripts:
       curl -fsSL https://raw.githubusercontent.com/KernAIO/app/main/selfhost/install.sh -o install.sh
   Do not run install.sh: it would generate new secrets. You already have them in .env.

2. Start only the infrastructure, so nothing migrates before the data is back:
       docker compose up -d postgres minio

3. Restore the database. db-init has not run yet, so create the role the dump expects first:
       docker compose up db-init
       docker compose exec -T postgres pg_restore -U $(env_value POSTGRES_USER) \\
           -d $(env_value POSTGRES_DB) --clean --if-exists < database.dump

4. Restore the files:
       docker compose run --rm --no-deps -v "\$PWD/files:/backup" --entrypoint /bin/sh minio-init \\
           -c "mc alias set dst '$S3_ENDPOINT' '<S3_ACCESS_KEY>' '<S3_SECRET_KEY>' &&
               mc mirror --overwrite /backup dst/$S3_BUCKET"
   The keys are in .env.

5. Start everything:
       docker compose up -d

The database and the files were captured a few seconds apart, not atomically. A file uploaded
during the backup may be in one and not the other.
EOS

# ---------------------------------------------------------------- prune

step "Pruning"
# Keep the newest $KEEP and no more, so backups cannot fill the disk on their own. Only directories
# that look like a stamp are considered, so nothing else in here is ever deleted.
mapfile -t OLD < <(ls -1d "$BACKUP_DIR"/[0-9]*-[0-9]*/ 2>/dev/null | sort -r | tail -n +"$((KEEP + 1))")
if [ "${#OLD[@]}" -gt 0 ]; then
  for old in "${OLD[@]}"; do
    rm -rf "$old"
    info "removed $(basename "$old")"
  done
else
  info "nothing to prune (keeping $KEEP)"
fi

printf '\n\033[32m✔ Backup complete: %s (%s)\033[0m\n' "$DEST" "$(du -sh "$DEST" | cut -f1)"
printf '  Restoring is described in %s/RESTORE.txt\n\n' "$DEST"
