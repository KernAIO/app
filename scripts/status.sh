#!/usr/bin/env bash
# git status summary across all repos
cd "$(dirname "$0")/.."
for d in . repos/*; do
  [ -d "$d/.git" ] || continue
  printf "\033[1m%-16s\033[0m %s\n" "$(basename "$(cd "$d" && pwd)")" "$(git -C "$d" status -sb | head -1)"
  git -C "$d" status --short | head -20
done
