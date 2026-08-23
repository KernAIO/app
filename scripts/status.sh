#!/usr/bin/env bash
#
# What every Kern checkout is holding that its remote does not have.
#
# Kern is one repository per service, so "is everything committed?" is a question with ten answers
# and no single `git status` that gives it. This asks all of them.
#
# Two things it deliberately does that a plain loop over `git status` does not:
#
#   * It finds every checkout, not just the ones under `repos/`. `website` sits beside the umbrella
#     rather than inside it, so a loop over `repos/*` misses it silently — which is the worst way to
#     miss something.
#   * It **fails** when anything needs attention, instead of only printing. A report nobody can gate
#     on is a report somebody forgets to read. Pass --quiet to get the exit code without the detail.
#
# Exit codes: 0 everything is pushed · 1 something is not · 2 a repository is missing entirely.

set -uo pipefail
cd "$(dirname "$0")/.."
UMBRELLA="$(pwd)"

QUIET=0
[ "${1:-}" = "--quiet" ] && QUIET=1

bold=$'\033[1m'; dim=$'\033[2m'; red=$'\033[31m'; yellow=$'\033[33m'; green=$'\033[32m'; off=$'\033[0m'
[ -t 1 ] || { bold=""; dim=""; red=""; yellow=""; green=""; off=""; }

say() { [ "$QUIET" = 1 ] || printf '%s\n' "$*"; }

dirty_total=0
missing_total=0

# Every checkout: the umbrella, everything cloned under repos/, and any sibling of the umbrella
# (that is where `website` lives). Resolved and de-duplicated, so a symlink cannot list one twice.
checkouts() {
  { echo "$UMBRELLA"
    for d in "$UMBRELLA"/repos/*/ "$UMBRELLA"/../*/; do
      [ -d "$d/.git" ] && (cd "$d" && pwd)
    done
  } | awk '!seen[$0]++'
}

# Repositories the organisation has, from the generated inventory, so a repo that was never cloned is
# reported rather than quietly absent.
expected() {
  local inv="$UMBRELLA/.claude/skills/kern-repos/references/inventory.md"
  [ -f "$inv" ] || return 0
  grep -oE '^\| \[`[a-z0-9._-]+`\]' "$inv" | tr -d '|[]` ' | sort -u
}

report() {
  local dir="$1" name issues=() count ahead behind stashes branch upstream
  name="$(basename "$dir")"

  count="$(git -C "$dir" status --porcelain | wc -l | tr -d ' ')"
  branch="$(git -C "$dir" rev-parse --abbrev-ref HEAD 2>/dev/null)"
  upstream="$(git -C "$dir" rev-parse --abbrev-ref '@{upstream}' 2>/dev/null || true)"
  stashes="$(git -C "$dir" stash list 2>/dev/null | wc -l | tr -d ' ')"

  if [ -n "$upstream" ]; then
    ahead="$(git -C "$dir" rev-list --count "$upstream"..HEAD 2>/dev/null || echo 0)"
    behind="$(git -C "$dir" rev-list --count HEAD.."$upstream" 2>/dev/null || echo 0)"
  else
    ahead=0; behind=0
  fi

  [ "$count"   -gt 0 ] && issues+=("$count uncommitted")
  [ "$ahead"   -gt 0 ] && issues+=("$ahead unpushed")
  [ "$stashes" -gt 0 ] && issues+=("$stashes stashed")
  [ -z "$upstream" ]   && issues+=("no upstream")
  [ "$branch" = "HEAD" ] && issues+=("detached HEAD")

  # Not a failure — a branch is a normal way to work — but worth seeing next to the rest.
  local note=""
  [ -n "$branch" ] && [ "$branch" != "main" ] && [ "$branch" != "HEAD" ] && note="${dim}on ${branch}${off}"
  [ "$behind" -gt 0 ] && note="$note ${dim}${behind} behind${off}"

  if [ ${#issues[@]} -eq 0 ]; then
    say "${green}✓${off} ${bold}$(printf '%-10s' "$name")${off} clean $note"
    return 0
  fi

  dirty_total=$((dirty_total + 1))
  local joined; joined="$(printf '%s, ' "${issues[@]}")"; joined="${joined%, }"
  say "${red}✗${off} ${bold}$(printf '%-10s' "$name")${off} ${joined} $note"

  # Every path, never a silent `head -n`: a truncated list reads exactly like a short one.
  if [ "$QUIET" = 0 ] && [ "$count" -gt 0 ]; then
    git -C "$dir" status --porcelain | sed 's/^/    /'
  fi
  if [ "$QUIET" = 0 ] && [ "$ahead" -gt 0 ]; then
    git -C "$dir" log --oneline "$upstream"..HEAD | sed 's/^/    ↑ /'
  fi

  # A published package changed with nothing to release it: the commit lands, CI goes green, the
  # registry keeps the old version, and the consumer still builds against the bug.
  if [ -d "$dir/.changeset" ] && { [ "$count" -gt 0 ] || [ "$ahead" -gt 0 ]; }; then
    if [ -z "$(find "$dir/.changeset" -maxdepth 1 -name '*.md' ! -name 'README.md' -print -quit)" ]; then
      say "    ${yellow}!${off} changes here, and no changeset — nothing would reach the registry"
    fi
  fi
  return 1
}

say ""
say "${bold}Kern checkouts${off} ${dim}— $UMBRELLA${off}"
say ""

found=""
while IFS= read -r dir; do
  [ -n "$dir" ] || continue
  report "$dir"
  found="$found $(basename "$dir")"
done < <(checkouts)

# Anything the organisation has that is not checked out anywhere here.
while IFS= read -r repo; do
  [ -n "$repo" ] || continue
  case " $found " in *" $repo "*) continue ;; esac
  missing_total=$((missing_total + 1))
  say "${yellow}?${off} ${bold}$(printf '%-10s' "$repo")${off} not checked out — run ${bold}pnpm setup${off}"
done < <(expected)

say ""
if [ "$missing_total" -gt 0 ]; then
  say "${yellow}${missing_total} repository/ies missing${off}, ${red}${dirty_total} with work not pushed${off}"
  exit 2
fi
if [ "$dirty_total" -gt 0 ]; then
  say "${red}${dirty_total} repository/ies have work that is not pushed.${off}"
  exit 1
fi
say "${green}Every checkout is clean and pushed.${off}"
