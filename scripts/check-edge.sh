#!/usr/bin/env bash
# What a stranger's browser sees at the edge of a Kern instance, checked from outside.
#
#   scripts/check-edge.sh [https://app.kernaio.com]
#
# Every rule here is one that a green build cannot see: the headers are written by Caddy and by
# core, the rate limit is enforced by core, and none of them exist in a unit test. It asks:
#   - the shell and the API both refuse to be framed and both send nosniff and a referrer policy;
#   - the API sends HSTS and answers with its rate-limit headers;
#   - sign-in is rate-limited — a burst of wrong passwords meets 429 well before it meets 20.
# Exit 1 on the first rule that fails, naming it. Run it against the cloud after a rollout and
# against a self-host after install.
set -euo pipefail
BASE="${1:-https://app.kernaio.com}"
fail() { echo "✗ $1"; exit 1; }
ok() { echo "✓ $1"; }

has() { # $1 headers, $2 name (case-insensitive), $3 substring the value must contain
  printf '%s' "$1" | grep -i "^$2:" | grep -qi -- "$3"
}

shell=$(curl -fsSI --max-time 20 "$BASE/") || fail "the shell does not answer at $BASE/"
api=$(curl -fsSI --max-time 20 "$BASE/api/health") || fail "the API does not answer at $BASE/api/health"

for name in shell api; do
  h=${!name}
  has "$h" "x-content-type-options" "nosniff" || fail "$name: no X-Content-Type-Options: nosniff"
  has "$h" "referrer-policy" "strict-origin" || fail "$name: no strict Referrer-Policy"
  has "$h" "content-security-policy" "frame-ancestors 'none'" || fail "$name: CSP does not carry frame-ancestors 'none'"
  has "$h" "x-frame-options" "DENY" || fail "$name: no X-Frame-Options: DENY"
  has "$h" "server" "caddy\|node\|express" && fail "$name: the Server header names the software"
  ok "$name: nosniff, referrer policy, frame-ancestors 'none', X-Frame-Options DENY"
done
has "$api" "strict-transport-security" "max-age=" || fail "api: no Strict-Transport-Security"
has "$shell" "strict-transport-security" "max-age=" || fail "shell: no Strict-Transport-Security"
ok "HSTS on the shell and the API"
has "$api" "x-ratelimit-limit" "" || fail "api: no X-RateLimit-Limit header, so the limiter is not in front of this route"
ok "the API answers with its rate-limit headers"

# A burst of wrong passwords. The limiter is per address; twenty is far more than a person types.
codes=""
for _ in $(seq 1 20); do
  codes+="$(curl -s -o /dev/null -w '%{http_code}' --max-time 15 -X POST "$BASE/api/auth/sign-in/email" \
    -H 'content-type: application/json' -d '{"email":"probe@example.invalid","password":"not-it"}') "
done
case "$codes" in
  *429*) ok "sign-in is rate-limited (${codes% })" ;;
  *) fail "sign-in answered twenty wrong passwords without a 429: ${codes% }" ;;
esac
