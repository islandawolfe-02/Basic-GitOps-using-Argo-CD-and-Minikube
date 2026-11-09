#!/usr/bin/env bash
# Receipt checks (W1.07 packaging gate / P1 smoke expectations) against a running foundation.
# Used by GitHub Actions and on the Mac (local run on 18080, port-forward on 18081). Bash 3.2 compatible.
# Usage: bash scripts/smoke.sh BASE_URL EXPECTED_LAB_ENV [EVIDENCE_DIR]
set -uo pipefail
base="${1:?usage: bash scripts/smoke.sh BASE_URL EXPECTED_LAB_ENV [EVIDENCE_DIR]}"
env_expected="${2:?usage: bash scripts/smoke.sh BASE_URL EXPECTED_LAB_ENV [EVIDENCE_DIR]}"
out="${3:-$(mktemp -d)}"
mkdir -p "$out"
root="$(cd "$(dirname "$0")/.." && pwd)"
fails=0
pass() { echo "PASS $*"; }
fail() { echo "FAIL $*"; fails=$((fails + 1)); }
header() { grep -i "^$1:" "$2" | head -1 | cut -d: -f2- | tr -d ' \r'; }

# Wait up to 30 s for a listener (a fresh container or port-forward may still be starting).
for _ in $(seq 1 30); do curl -s -m 2 -o /dev/null "$base/healthz" && break; sleep 1; done

health="$(curl -s -m 5 "$base/healthz")"
[ "$health" = "Healthy" ] && pass "GET /healthz -> Healthy" || fail "GET /healthz -> '$health' (expected Healthy)"

code="$(curl -s -m 5 -o "$out/page.html" -w '%{http_code}' "$base/")"
[ "$code" = 200 ] && grep -q 'Treasure hunt board preview' "$out/page.html" \
  && pass "GET / -> 200 foundation page" || fail "GET / -> $code (expected 200 foundation page)"
code="$(curl -s -m 5 -o "$out/app.js" -w '%{http_code}' "$base/app.js")"
cmp -s "$out/app.js" "$root/app/wwwroot/app.js" && pass "GET /app.js -> $code, equals app/wwwroot/app.js" \
  || fail "GET /app.js -> $code, differs from app/wwwroot/app.js (the page cannot call the API)"

rid="smoke-$(date -u +%Y%m%dT%H%M%SZ)-$$"
code="$(curl -s -m 5 -H "X-Request-Id: $rid" -D "$out/reference-headers.txt" -o "$out/reference-board.json" \
  -w '%{http_code}' "$base/api/boards/reference")"
[ "$code" = 200 ] && pass "GET /api/boards/reference -> 200" || fail "GET /api/boards/reference -> $code (expected 200)"
cmp -s "$out/reference-board.json" "$root/app/data/board-reference.json" \
  && pass "reference body equals app/data/board-reference.json (3x3, 6 initial moves)" \
  || fail "reference body differs from app/data/board-reference.json"
release="$(header X-Lab-Release "$out/reference-headers.txt")"
[ "$release" = foundation-observe-a ] && pass "X-Lab-Release: $release" || fail "X-Lab-Release: '$release' (expected foundation-observe-a)"
environment="$(header X-Lab-Environment "$out/reference-headers.txt")"
[ "$environment" = "$env_expected" ] && pass "X-Lab-Environment: $environment" \
  || fail "X-Lab-Environment: '$environment' (expected $env_expected)"
echoed="$(header X-Request-Id "$out/reference-headers.txt")"
[ "$echoed" = "$rid" ] && pass "X-Request-Id echoed: $rid" || fail "X-Request-Id: '$echoed' (expected $rid)"

code="$(curl -s -m 5 -o "$out/missing-board.json" -w '%{http_code}' "$base/api/boards/missing")"
[ "$code" = 404 ] && grep -q '"code":"NOT_FOUND"' "$out/missing-board.json" \
  && pass "GET /api/boards/missing -> 404 NOT_FOUND" || fail "GET /api/boards/missing -> $code (expected 404 NOT_FOUND)"

echo "request_id=$rid  (Grafana: {job=\"academy-w110\", session=\"<P1_SESSION>\"} | json | request_id=\"$rid\")"
echo "evidence files: $out"
if [ "$fails" -eq 0 ]; then echo "RESULT: PASS"; else echo "RESULT: FAIL ($fails check(s))"; exit 1; fi
