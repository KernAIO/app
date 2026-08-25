#!/usr/bin/env bash
# Runs a pnpm script in every checked-out Kern repository, in dependency order.
#
# The umbrella cannot own a turbo task graph: each repo carries its own turbo.json
# and CI clones it alone, so that file has to be a *root* config — and turbo rejects
# the `extends: ["//"]` a package-level config inside this workspace would need.
# Rather than keep two incompatible shapes in one file, the umbrella just drives
# each repo's own scripts.
#
#   scripts/run-all.sh typecheck            # sequential, stops nothing, reports every failure
#   scripts/run-all.sh dev --parallel       # all at once, Ctrl-C kills the group
set -uo pipefail
cd "$(dirname "$0")/.."

TASK="${1:?usage: run-all.sh <task> [--parallel]}"
MODE="${2:-}"
ORDER=(kernel module-tracker module-chat module-quire module-hr module-mail module-billing module-template core collab app docs)

has_script() {
  node -e "const s=require('./repos/$1/package.json').scripts||{};process.exit(s['$TASK']?0:1)" 2>/dev/null
}

targets=()
for r in "${ORDER[@]}"; do
  [ -f "repos/$r/package.json" ] || continue
  has_script "$r" && targets+=("$r")
done

if [ ${#targets[@]} -eq 0 ]; then
  echo "no repository has a \"$TASK\" script — nothing to run"
  exit 0
fi

fail=0
failed=()

if [ "$MODE" = "--parallel" ]; then
  trap 'kill 0' INT TERM
  pids=()
  for r in "${targets[@]}"; do
    (cd "repos/$r" && pnpm "$TASK" 2>&1 | sed "s/^/[$r] /") &
    pids+=("$!")
  done
  for p in "${pids[@]}"; do wait "$p" || fail=1; done
else
  for r in "${targets[@]}"; do
    printf '\n\033[1m▸ %s — %s\033[0m\n' "$r" "$TASK"
    if ! (cd "repos/$r" && pnpm "$TASK"); then
      fail=1
      failed+=("$r")
    fi
  done
fi

if [ "$fail" -ne 0 ] && [ ${#failed[@]} -gt 0 ]; then
  printf '\n\033[31m✗ %s failed in: %s\033[0m\n' "$TASK" "${failed[*]}"
fi
exit "$fail"
