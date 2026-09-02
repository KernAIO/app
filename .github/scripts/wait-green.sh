#!/usr/bin/env bash
# Wait until a commit's CI has finished, and say whether it passed.
#
#   .github/scripts/wait-green.sh <owner/repo> <sha> [timeout-minutes]
#
# Exits 0 when a completed `ci.yml` run for the commit concluded `success`, 1 when one concluded
# anything else, and 2 when nothing completed inside the timeout. A run that is still in progress
# is waited for — reading "the latest run's conclusion" the moment after a push sees `null` and
# calls a green commit red, which is what this used to do.
#
# Needs GH_TOKEN able to read Actions on that repository.
set -euo pipefail

REPO="$1"
SHA="$2"
TIMEOUT_MIN="${3:-45}"
DEADLINE=$(( $(date +%s) + TIMEOUT_MIN * 60 ))

while :; do
  # Every run for this commit, newest first — a branch push and a later push to main share a sha.
  RUNS=$(gh api "/repos/$REPO/actions/workflows/ci.yml/runs?head_sha=$SHA&per_page=20" \
    --jq '[.workflow_runs[] | {status, conclusion}]')
  COMPLETED=$(echo "$RUNS" | jq -r '[.[] | select(.status == "completed")] | length')
  if [ "$COMPLETED" -gt 0 ]; then
    # If any completed run passed, the commit is good; a cancelled twin does not make it bad.
    if echo "$RUNS" | jq -e '[.[] | select(.status == "completed" and .conclusion == "success")] | length > 0' >/dev/null; then
      echo "$REPO@${SHA:0:8}: CI green"
      exit 0
    fi
    if echo "$RUNS" | jq -e '[.[] | select(.status == "completed" and .conclusion != "cancelled" and .conclusion != "skipped")] | length > 0' >/dev/null; then
      echo "$REPO@${SHA:0:8}: CI $(echo "$RUNS" | jq -r '[.[] | select(.status == "completed")][0].conclusion')"
      exit 1
    fi
  fi
  if [ "$(date +%s)" -ge "$DEADLINE" ]; then
    echo "$REPO@${SHA:0:8}: CI did not finish within ${TIMEOUT_MIN} minutes"
    exit 2
  fi
  sleep 30
done
