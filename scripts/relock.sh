#!/usr/bin/env bash
# Refresh a repository's own pnpm-lock.yaml.
#
#   scripts/relock.sh <repo> [<repo> ...]        # names under repos/
#
# CI installs from the lockfile committed in each repository. Adding a dependency from inside the
# umbrella updates the *umbrella* lockfile and leaves that one stale, so every job fails at
# ERR_PNPM_OUTDATED_LOCKFILE — install-time, before a single test runs. It is not obvious, because
# nothing local ever reads the file that broke.
#
# It cannot be refreshed in place either: plain `pnpm install` in repos/<name> walks up and attaches
# to the umbrella, and `--ignore-workspace` skips packages/* and reports nothing to do. So this
# clones the repository somewhere else, resolves there, and copies the result back.
set -euo pipefail
UMBRELLA="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

[ $# -gt 0 ] || { echo "usage: scripts/relock.sh <repo> [<repo> ...]" >&2; exit 1; }

for name in "$@"; do
  repo="$UMBRELLA/repos/$name"
  [ -d "$repo/.git" ] || { echo "  $name: not a checkout under repos/, skipping" >&2; continue; }
  [ -f "$repo/pnpm-lock.yaml" ] || { echo "  $name: commits no lockfile, nothing to refresh"; continue; }

  git clone -q "file://$repo" "$WORK/$name"
  # the working tree, not HEAD: the point is to lock what is about to be committed
  ( cd "$repo" && git ls-files -z '*package.json' ) | while IFS= read -r -d '' f; do
    mkdir -p "$WORK/$name/$(dirname "$f")"
    cp "$repo/$f" "$WORK/$name/$f"
  done
  ( cd "$WORK/$name" && pnpm install --lockfile-only >/dev/null 2>&1 )
  cp "$WORK/$name/pnpm-lock.yaml" "$repo/pnpm-lock.yaml"
  echo "  $name: lockfile refreshed"
done
