#!/usr/bin/env bash
set -euo pipefail

# =========================
# CONFIG
# =========================

BASE="${BASE:-http://127.0.0.1:8081}"
OP="${OP:-default}"
API_KEY="${API_KEY:-default_secret_key}"
SECRET="${SECRET:-default_secret_key}"
CURRENCY="${CURRENCY:-VND}"
GAME_ID="${GAME_ID:-bacay}"

DEPOSIT_AMOUNT="${DEPOSIT_AMOUNT:-10000}"
WITHDRAW_AMOUNT="${WITHDRAW_AMOUNT:-3000}"

USER="curlv2_$(date +%s)"
TXN="txn_${USER}"
WITHDRAW_TXN="${TXN}_w"

# =========================
# HELPERS (FIXED PARSER)
# =========================

print_json() {
  echo "$1"
}

json_get_string() {
  echo "$1" | grep -o "\"$2\"[[:space:]]*:[[:space:]]*\"[^\"]*\"" | head -n 1 | sed "s/.*\"$2\"[[:space:]]*:[[:space:]]*\"\([^\"]*\)\".*/\1/"
}

json_get_number() {
  echo "$1" | grep -o "\"$2\"[[:space:]]*:[[:space:]]*[0-9][0-9.]*" | head -n 1 | sed "s/.*\"$2\"[[:space:]]*:[[:space:]]*//"
}

json_get_bool() {
  echo "$1" | grep -o "\"$2\"[[:space:]]*:[[:space:]]*\(true\|false\)" | head -n 1 | sed "s/.*\"$2\"[[:space:]]*:[[:space:]]*//"
}

assert_success() {
  local step="$1"
  local json="$2"

  local success
  success=$(json_get_bool "$json" "success")

  if [ "$success" != "true" ]; then
    echo
    echo "❌ FAILED at step: $step"
    echo "Response:"
    print_json "$json"
    exit 1
  fi
}

call_api() {
  local step="$1"
  local url="$2"
  local body="$3"
  shift 3

  echo
  echo "=============================="
  echo "$step"
  echo "=============================="

  local response
  response=$(curl -s -X POST "$url" \
    -H "Content-Type: application/json" \
    "$@" \
    -d "$body")

  print_json "$response"
  assert_success "$step" "$response"

  LAST_RESPONSE="$response"
}

# =========================
# START
# =========================

echo "======================================"
echo " V2 AUTO TEST FLOW - BASH ONLY"
echo "======================================"
echo "BASE: $BASE"
echo "USER: $USER"
echo "======================================"

# =========================
# 1. GET ACCESS TOKEN
# =========================

echo
echo "=============================="
echo "1. Get access token"
echo "=============================="

TS="$(date +%s000)"

SIG="$(printf "%s" "${OP}${API_KEY}${TS}" \
  | openssl dgst -sha256 -hmac "$SECRET" -binary \
  | openssl base64 \
  | tr -d '\n')"

TOKEN_JSON=$(curl -s -X POST "$BASE/api/v2/4001" \
  -H "Content-Type: application/json" \
  -d "{\"operatorCode\":\"$OP\",\"apiKey\":\"$API_KEY\",\"timestamp\":$TS,\"signature\":\"$SIG\"}")

print_json "$TOKEN_JSON"
assert_success "Get access token" "$TOKEN_JSON"

ACCESS_TOKEN="$(json_get_string "$TOKEN_JSON" "accessToken")"
REFRESH_TOKEN="$(json_get_string "$TOKEN_JSON" "refreshToken")"

if [ -z "$ACCESS_TOKEN" ]; then
  echo "❌ Cannot extract accessToken"
  exit 1
fi

echo "✅ Access token OK"

# =========================
# 2. CREATE ACCOUNT
# =========================

call_api \
  "2. Create account" \
  "$BASE/api/v2/4011" \
  "{\"operatorCode\":\"$OP\",\"username\":\"$USER\",\"currency\":\"$CURRENCY\"}" \
  -H "Authorization: Bearer $ACCESS_TOKEN" \
  -H "X-Request-Id: create-$USER"

# =========================
# 3. CHECK BALANCE
# =========================

call_api \
  "3. Check balance" \
  "$BASE/api/v2/4012" \
  "{\"operatorCode\":\"$OP\",\"username\":\"$USER\"}" \
  -H "Authorization: Bearer $ACCESS_TOKEN"

# =========================
# 4. DEPOSIT
# =========================

call_api \
  "4. Deposit" \
  "$BASE/api/v2/4021" \
  "{\"operatorCode\":\"$OP\",\"username\":\"$USER\",\"transactionId\":\"$TXN\",\"type\":\"DEPOSIT\",\"amount\":$DEPOSIT_AMOUNT,\"currency\":\"$CURRENCY\"}" \
  -H "Authorization: Bearer $ACCESS_TOKEN"

# =========================
# 5. LAUNCH GAME
# =========================

call_api \
  "5. Launch game" \
  "$BASE/api/v2/4031" \
  "{\"operatorCode\":\"$OP\",\"username\":\"$USER\",\"gameId\":\"$GAME_ID\",\"platform\":\"WEB\"}" \
  -H "Authorization: Bearer $ACCESS_TOKEN"

# =========================
# 6. WITHDRAW
# =========================

call_api \
  "6. Withdraw" \
  "$BASE/api/v2/4021" \
  "{\"operatorCode\":\"$OP\",\"username\":\"$USER\",\"transactionId\":\"$WITHDRAW_TXN\",\"type\":\"WITHDRAW\",\"amount\":$WITHDRAW_AMOUNT,\"currency\":\"$CURRENCY\"}" \
  -H "Authorization: Bearer $ACCESS_TOKEN"

# =========================
# 7. FINAL BALANCE CHECK
# =========================

call_api \
  "7. Final balance" \
  "$BASE/api/v2/4012" \
  "{\"operatorCode\":\"$OP\",\"username\":\"$USER\"}" \
  -H "Authorization: Bearer $ACCESS_TOKEN"

FINAL_BALANCE="$(json_get_number "$LAST_RESPONSE" "balance")"
EXPECTED_BALANCE=$((DEPOSIT_AMOUNT - WITHDRAW_AMOUNT))

echo
echo "Expected: $EXPECTED_BALANCE"
echo "Actual:   $FINAL_BALANCE"

if [ "$FINAL_BALANCE" != "$EXPECTED_BALANCE" ]; then
  echo "❌ Balance mismatch"
  exit 1
fi

# =========================
# DONE
# =========================

echo
echo "======================================"
echo "✅ FULL FLOW PASSED"
echo "======================================"
echo "USER: $USER"
echo "FINAL_BALANCE: $FINAL_BALANCE"
echo "======================================"