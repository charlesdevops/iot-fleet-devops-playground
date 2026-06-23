#!/usr/bin/env bash
# Smoke test: hit the app endpoints and verify AWS state on LocalStack.
# Usage: smoke.sh <app-url> [localstack-url]
set -uo pipefail

APP_URL="${1:-http://localhost:8000}"
LOCALSTACK_URL="${2:-http://localhost:4566}"
AWS=(env AWS_ACCESS_KEY_ID=test AWS_SECRET_ACCESS_KEY=test AWS_DEFAULT_REGION=us-east-1 aws --endpoint-url "$LOCALSTACK_URL")

results=()

check() {
  local name="$1" rc="$2"
  [[ $rc -eq 0 ]] && results+=("$name|PASS") || results+=("$name|FAIL")
}

summary() {
  echo ""
  printf "┌──────────────────────┬──────────┐\n"
  printf "│ %-20s │  Result  │\n" "Check"
  printf "├──────────────────────┼──────────┤\n"
  for entry in "${results[@]}"; do
    IFS='|' read -r name result <<< "$entry"
    [[ "$result" == "PASS" ]] && color="\033[32m" || color="\033[31m"
    printf "│ %-20s │  ${color}%-4s\033[0m  │\n" "$name" "$result"
  done
  printf "└──────────────────────┴──────────┘\n"
}

# ── health ────────────────────────────────────────────────────────────────────
echo "==> health"
result=$(curl -sf "$APP_URL/healthz" 2>/dev/null); rc=$?
[[ $rc -eq 0 ]] && echo "$result" | jq .
check "health" $rc

# ── register device ─────────────────────────────────────────────────────────────
echo "==> register device"
printf "smoke" > /tmp/smoke.bin
result=$(curl -sf -X POST "$APP_URL/devices" \
  -F "device_id=dev-smoke" -F "model=acme-edge-100" \
  -F "firmware=@/tmp/smoke.bin;type=application/octet-stream" 2>/dev/null); rc=$?
[[ $rc -eq 0 ]] && echo "$result" | jq .
check "register device" $rc

# ── list devices ──────────────────────────────────────────────────────────────
echo "==> list devices"
result=$(curl -sf "$APP_URL/devices" 2>/dev/null); rc=$?
[[ $rc -eq 0 ]] && echo "$result" | jq .
check "list devices" $rc

# ── DynamoDB scan ─────────────────────────────────────────────────────────────
echo "==> DynamoDB scan"
"${AWS[@]}" dynamodb scan --table-name devices-local --output table
check "DynamoDB scan" $?

# ── S3 objects ────────────────────────────────────────────────────────────────
echo "==> S3 objects"
"${AWS[@]}" s3 ls s3://fleet-firmware-local --recursive
check "S3 objects" $?

summary
