#!/usr/bin/env bash
# Go back to the version an upgrade snapshot was taken from.
#
#   ./kern-rollback.sh                       use the newest snapshot
#   ./kern-rollback.sh snapshots/1.1.0-to-1.2.0-20260822-140301
#   ./kern-rollback.sh <snapshot> --database  also restore the database
#
# Images roll back on their own. The database does not: migrations only go forwards. Within a minor
# release that is fine, because a migration must stay compatible with the image before it — so the
# older image runs against the newer schema. Across a release that changed the schema in a way it
# could not (the release notes say so), pass --database and accept losing what was written since the
# snapshot was taken.
set -euo pipefail

DIR="${KERN_DIR:-$(cd "$(dirname "$0")" && pwd)}"
cd "$DIR"

SNAPSHOT_DIR="${KERN_SNAPSHOT_DIR:-$DIR/snapshots}"

step() { printf '\n\033[1m==> %s\033[0m\n' "$1"; }
info() { printf '    %s\n' "$1"; }
fail() { printf '\n\033[31m✖ %s\033[0m\n' "$1" >&2; exit 1; }

RESTORE_DB=false
SNAP=""
for arg in "$@"; do
  case "$arg" in
    --database) RESTORE_DB=true ;;
    -*) fail "Unknown option: $arg" ;;
    *) SNAP="$arg" ;;
  esac
done

if [ -z "$SNAP" ]; then
  SNAP="$(ls -1dt "$SNAPSHOT_DIR"/*/ 2>/dev/null | head -1 || true)"
  [ -n "$SNAP" ] || fail "No snapshots in $SNAPSHOT_DIR. Pass one, or set KERN_VERSION in .env by hand."
fi
SNAP="${SNAP%/}"
[ -d "$SNAP" ] || fail "No such snapshot: $SNAP"
[ -f "$SNAP/from-version" ] || fail "$SNAP has no from-version file, so there is nothing to go back to."

FROM="$(cat "$SNAP/from-version")"
CURRENT="$(grep -E '^KERN_VERSION=' .env | head -1 | cut -d= -f2- | tr -d '"')"
info "Now:        $CURRENT"
info "Going back to: $FROM"
info "Snapshot:   $SNAP"

step "Closing the API"
docker compose run --rm core node dist/migrate.js --maintenance on || info "could not close the API; carrying on"

if [ "$RESTORE_DB" = true ]; then
  [ -f "$SNAP/database.dump" ] || fail "$SNAP has no database.dump."
  printf '\n\033[31mThis replaces the database with the snapshot. Everything written since %s is lost.\033[0m\n' \
    "$(basename "$SNAP")"
  read -rp "Type the word restore to continue: " confirm
  [ "$confirm" = "restore" ] || fail "Nothing was changed."

  step "Restoring the database"
  docker compose stop core core-worker chat mail collab app >/dev/null 2>&1 || true
  docker compose exec -T postgres pg_restore \
    -U "$(grep -E '^POSTGRES_USER=' .env | cut -d= -f2-)" \
    -d "$(grep -E '^POSTGRES_DB=' .env | cut -d= -f2-)" \
    --clean --if-exists < "$SNAP/database.dump" || fail "The restore failed. The instance is down; fix this before starting it."
  info "database restored"
fi

step "Putting $FROM back"
sed -i.bak "s|^KERN_VERSION=.*|KERN_VERSION=$FROM|" .env && rm -f .env.bak
docker compose pull
docker compose up -d

step "Opening the API again"
sleep 5
docker compose run --rm core node dist/migrate.js --maintenance off || info "could not clear maintenance mode; it expires on its own after 30 minutes"

printf '\n\033[32m✔ Kern is back on %s.\033[0m\n' "$FROM"
if [ "$RESTORE_DB" = false ]; then
  printf '  The database was left as it is. If the release changed the schema in a way the old\n'
  printf '  images cannot read, run this again with --database.\n\n'
fi
