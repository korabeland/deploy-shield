#!/usr/bin/env bash
# Post-deploy smoke test: proves the deployed service actually serves
# requests.
#
# A `vercel deploy` that exits 0 only proves the upload succeeded. Nothing
# else in the four gate tiers ever executes the built artifact — vitest
# transpiles TypeScript and tsc only checks types — so a service can ship
# green and fail every request. This template shipped exactly that twice:
# once with a missing runtime dependency (HTTP 500) and once with handlers in
# an export shape Vercel never invokes (hung to a 504).
#
# Usage: smoke-test.sh <deployment-url>
# Env:   BYPASS (optional) — Vercel Protection Bypass for Automation secret,
#        required when the deployment is protected.

set -euo pipefail

BASE_URL="${1:?usage: smoke-test.sh <deployment-url>}"
ATTEMPTS="${SMOKE_ATTEMPTS:-3}"
# --max-time is load-bearing: a handler that never ends its response leaves an
# uncapped curl hanging until the platform's function timeout, which burns the
# whole job budget and reports a cancelled run instead of a failed one.
TIMEOUT="${SMOKE_TIMEOUT:-20}"

probe() {
  local path="$1" out="$2"
  shift 2
  curl -s --max-time "$TIMEOUT" -o "$out" -w '%{http_code}' \
    ${BYPASS:+-H "x-vercel-protection-bypass: $BYPASS"} \
    "$@" "${BASE_URL}${path}" || echo 000
}

health_body="$(mktemp)"
echo_body="$(mktemp)"
trap 'rm -f "$health_body" "$echo_body"' EXIT

health_code=""
echo_code=""

attempt=1
while [ "$attempt" -le "$ATTEMPTS" ]; do
  health_code=$(probe /api/health "$health_body")
  # Exercise POST as well: the two endpoints use different HTTP-method
  # exports, so a routing regression can break one while the other answers.
  echo_code=$(probe /api/echo "$echo_body" \
    -X POST -H 'content-type: application/json' \
    -d '{"message":"smoke"}')

  if [ "$health_code" = "200" ] && [ "$echo_code" = "200" ]; then
    echo "GET  /api/health -> 200 $(cat "$health_body")"
    echo "POST /api/echo   -> 200 $(cat "$echo_body")"
    echo "Smoke test passed against ${BASE_URL}"
    exit 0
  fi

  echo "Attempt ${attempt}/${ATTEMPTS}: health=${health_code} echo=${echo_code}"
  attempt=$((attempt + 1))
  [ "$attempt" -le "$ATTEMPTS" ] && sleep 5
done

{
  echo "::error::Smoke test failed against ${BASE_URL} —" \
    "health=${health_code} echo=${echo_code} (expected 200/200)." \
    "The deployment uploaded but the service does not serve requests." \
    "HTTP 000 means the request timed out; 401/302 means the deployment is" \
    "protected and BYPASS is missing or wrong."
  cat "$health_body" "$echo_body" 2>/dev/null || true
} >&2
exit 1
