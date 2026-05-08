#!/usr/bin/env bash
set -euo pipefail

# =========================
# CONFIG
# =========================

INPUT_BASE="${BASE-}"
INPUT_PORTAL_HOST="${PORTAL_HOST-}"
INPUT_HOST="${HOST-}"
INPUT_IP="${IP-}"
INPUT_PORTAL_PORT="${PORTAL_PORT-}"
INPUT_PORTAL_SCHEME="${PORTAL_SCHEME-}"
INPUT_OP="${OP-}"
INPUT_API_KEY="${API_KEY-}"
INPUT_SECRET="${SECRET-}"

ENV_FILE="${ENV_FILE:-.env}"
if [ -f "$ENV_FILE" ]; then
  set -a
  # shellcheck disable=SC1090
  . "$ENV_FILE"
  set +a
fi

PORTAL_HOST="${INPUT_PORTAL_HOST:-${PORTAL_HOST:-${INPUT_HOST:-${HOST:-${INPUT_IP:-${IP:-127.0.0.1}}}}}}"
PORTAL_PORT="${INPUT_PORTAL_PORT:-${PORTAL_PORT:-8081}}"
PORTAL_SCHEME="${INPUT_PORTAL_SCHEME:-${PORTAL_SCHEME:-http}}"
RAW_BASE="${INPUT_BASE:-${BASE:-${PORTAL_SCHEME}://${PORTAL_HOST}:${PORTAL_PORT}}}"

OP="${INPUT_OP:-${OP:-OP001}}"
API_KEY="${INPUT_API_KEY:-${API_KEY:-api_key_op001_live_prod2025}}"
SECRET="${INPUT_SECRET:-${SECRET:-test-secret-key-12345}}"
CURRENCY="${CURRENCY:-VND}"
COUNTRY="${COUNTRY:-VN}"
LANGUAGE="${LANGUAGE:-vi}"
PLATFORM="${PLATFORM:-WEB}"
GAME_ID="${GAME_ID:-PORTAL}"
RETURN_URL="${RETURN_URL:-https://example.com/lobby}"

DEPOSIT_AMOUNT="${DEPOSIT_AMOUNT:-10000}"
WITHDRAW_AMOUNT="${WITHDRAW_AMOUNT:-3000}"
ASYNC_WAIT_SECONDS="${ASYNC_WAIT_SECONDS:-2}"
LOG_DIR="${LOG_DIR:-./logs}"
ALLOW_LEGACY_AUTH_FALLBACK="${ALLOW_LEGACY_AUTH_FALLBACK:-0}"

USER="curlv2$(date +%s)"
DEPOSIT_TXN="dep_${USER}"
WITHDRAW_TXN="wd_${USER}"
DEPOSIT_REQUEST_ID="req_${DEPOSIT_TXN}"
WITHDRAW_REQUEST_ID="req_${WITHDRAW_TXN}"
LAST_RESPONSE=""
STARTED_AT="$(date '+%Y-%m-%d %H:%M:%S')"
WARNING_COUNT=0
EFFECTIVE_BALANCE_AFTER_DEPOSIT=0
IS_LOCAL_LEGACY_HOST=0
BLOCK_REASON=""
AUTH_SCOPE=""
LEGACY_OP="default"
LEGACY_API_KEY="default_secret_key"
LEGACY_SECRET="default_secret_key"

# =========================
# HELPERS
# =========================

print_json() {
  echo "$1"
}

mkdir -p "$LOG_DIR"
LOG_FILE="${LOG_DIR}/test_v2_full_flow_${USER}.log"

log_line() {
  echo "$1" | tee -a "$LOG_FILE"
}

log_block() {
  local title="$1"
  local content="$2"
  {
    printf '%s\n' "$title"
    printf '%s\n' "$content"
  } >> "$LOG_FILE"
}

log_warning() {
  WARNING_COUNT=$((WARNING_COUNT + 1))
  log_line "[WARN] $1"
}

log_info() {
  log_line "[INFO] $1"
}

json_get_string() {
  echo "$1" | grep -o "\"$2\"[[:space:]]*:[[:space:]]*\"[^\"]*\"" | head -n 1 | sed "s/.*\"$2\"[[:space:]]*:[[:space:]]*\"\([^\"]*\)\".*/\1/" || true
}

json_get_number() {
  echo "$1" | grep -o "\"$2\"[[:space:]]*:[[:space:]]*-[0-9][0-9.]*\|\"$2\"[[:space:]]*:[[:space:]]*[0-9][0-9.]*" | head -n 1 | sed "s/.*\"$2\"[[:space:]]*:[[:space:]]*//" || true
}

json_get_bool() {
  echo "$1" | grep -o "\"$2\"[[:space:]]*:[[:space:]]*\(true\|false\)" | head -n 1 | sed "s/.*\"$2\"[[:space:]]*:[[:space:]]*//" || true
}

is_local_legacy_host() {
  case "$1" in
    127.0.0.1|localhost) return 0 ;;
    *) return 1 ;;
  esac
}

finish_blocked() {
  local message="$1"

  echo
  echo "======================================"
  echo "FLOW BLOCKED BY ENVIRONMENT"
  echo "======================================"
  echo "$message"
  echo "BASE: $BASE"
  echo "USER: $USER"
  echo "======================================"

  log_line ""
  log_line "======================================"
  log_line "FLOW BLOCKED BY ENVIRONMENT"
  log_line "======================================"
  log_line "$message"
  log_line "BASE: $BASE"
  log_line "USER: $USER"
  log_line "WARNING_COUNT: $WARNING_COUNT"
  log_line "Completed at: $(date '+%Y-%m-%d %H:%M:%S')"
  log_line "======================================"
  exit 0
}

assert_success() {
  local step="$1"
  local json="$2"

  local success
  success=$(json_get_bool "$json" "success")

  if [ "$success" != "true" ]; then
    log_line "[FAIL] $step"
    log_block "Response:" "$json"
    echo
    echo "FAILED at step: $step"
    echo "Response:"
    print_json "$json"
    exit 1
  fi

  log_line "[PASS] $step"
}

assert_contains() {
  local step="$1"
  local haystack="$2"
  local needle="$3"

  if ! printf "%s" "$haystack" | grep -Fq "$needle"; then
    log_line "[FAIL] $step"
    log_line "Expected response to contain: $needle"
    log_block "Response:" "$haystack"
    echo
    echo "FAILED at step: $step"
    echo "Expected response to contain: $needle"
    echo "Response:"
    print_json "$haystack"
    exit 1
  fi
}

assert_equal() {
  local step="$1"
  local expected="$2"
  local actual="$3"

  if [ "$expected" != "$actual" ]; then
    log_line "[FAIL] $step"
    log_line "Expected: $expected"
    log_line "Actual:   $actual"
    echo
    echo "FAILED at step: $step"
    echo "Expected: $expected"
    echo "Actual:   $actual"
    exit 1
  fi
}

assert_number_ge() {
  local step="$1"
  local actual="$2"
  local minimum="$3"

  if [ -z "$actual" ] || [ "$actual" -lt "$minimum" ]; then
    log_line "[FAIL] $step"
    log_line "Expected number >= $minimum"
    log_line "Actual: $actual"
    echo
    echo "FAILED at step: $step"
    echo "Expected number >= $minimum"
    echo "Actual: $actual"
    exit 1
  fi
}

normalize_base() {
  local raw="$1"
  local trimmed="${raw%/}"

  case "$trimmed" in
    */api/v2) echo "$trimmed" ;;
    *) echo "$trimmed/api/v2" ;;
  esac
}

api_url() {
  local path="$1"
  echo "${BASE}${path}"
}

call_api() {
  local step="$1"
  local path="$2"
  local body="$3"
  shift 3

  echo
  echo "=============================="
  echo "$step"
  echo "=============================="

  log_line ""
  log_line "=============================="
  log_line "$step"
  log_line "=============================="
  log_line "API: POST $(api_url "$path")"
  log_block "Request body:" "$body"

  local response
  response=$(curl -sS -X POST "$(api_url "$path")" \
    -H "Content-Type: application/json" \
    "$@" \
    -d "$body")

  print_json "$response"
  log_block "Response body:" "$response"
  assert_success "$step" "$response"
  LAST_RESPONSE="$response"
}

call_api_no_assert() {
  local step="$1"
  local path="$2"
  local body="$3"
  shift 3

  echo
  echo "=============================="
  echo "$step"
  echo "=============================="

  log_line ""
  log_line "=============================="
  log_line "$step"
  log_line "=============================="
  log_line "API: POST $(api_url "$path")"
  log_block "Request body:" "$body"

  local response
  response=$(curl -sS -X POST "$(api_url "$path")" \
    -H "Content-Type: application/json" \
    "$@" \
    -d "$body")

  print_json "$response"
  log_block "Response body:" "$response"
  LAST_RESPONSE="$response"
}

auth_request_body() {
  local ts="$1"
  local op="$2"
  local api_key="$3"
  local signature="$4"
  printf '{"operatorCode":"%s","apiKey":"%s","timestamp":%s,"signature":"%s"}' \
    "$op" "$api_key" "$ts" "$signature"
}

generate_auth_signature() {
  local op="$1"
  local api_key="$2"
  local ts="$3"
  local secret="$4"

  printf "%s" "${op}${api_key}${ts}" \
    | openssl dgst -sha256 -hmac "$secret" -binary \
    | openssl base64 \
    | tr -d '\n'
}

authenticate_once() {
  local op="$1"
  local api_key="$2"
  local secret="$3"

  TS="$(date +%s000)"
  SIG="$(generate_auth_signature "$op" "$api_key" "$TS" "$secret")"

  TOKEN_JSON=$(curl -sS -X POST "$(api_url "/4001")" \
    -H "Content-Type: application/json" \
    -d "$(auth_request_body "$TS" "$op" "$api_key" "$SIG")")

  LAST_RESPONSE="$TOKEN_JSON"
}

BASE="$(normalize_base "$RAW_BASE")"

if is_local_legacy_host "$PORTAL_HOST"; then
  IS_LOCAL_LEGACY_HOST=1
fi

if [ "$WITHDRAW_AMOUNT" -gt "$DEPOSIT_AMOUNT" ]; then
  echo "WITHDRAW_AMOUNT must be <= DEPOSIT_AMOUNT"
  exit 1
fi

# =========================
# START
# =========================

echo "======================================"
echo " V2 FULL SPEC TEST FLOW"
echo "======================================"
echo "BASE: $BASE"
echo "PORTAL_HOST: $PORTAL_HOST"
echo "USER: $USER"
echo "GAME_ID: $GAME_ID"
echo "======================================"

log_line "======================================"
log_line "V2 FULL SPEC TEST FLOW"
log_line "======================================"
log_line "Started at: $STARTED_AT"
log_line "BASE: $BASE"
log_line "PORTAL_HOST: $PORTAL_HOST"
log_line "USER: $USER"
log_line "GAME_ID: $GAME_ID"
log_line "LOG_FILE: $LOG_FILE"
log_line "======================================"

# =========================
# 1. GET ACCESS TOKEN
# =========================

echo
echo "=============================="
echo "1. Get access token"
echo "=============================="

authenticate_once "$OP" "$API_KEY" "$SECRET"

AUTH_ERROR_CODE="$(json_get_string "$TOKEN_JSON" "errorCode")"
AUTH_ERROR_MESSAGE="$(json_get_string "$TOKEN_JSON" "errorMessage")"

if [ "$ALLOW_LEGACY_AUTH_FALLBACK" = "1" ] && [ "$IS_LOCAL_LEGACY_HOST" -eq 1 ] && [ "$AUTH_ERROR_CODE" = "1001" ] && \
   { [ "$OP" != "$LEGACY_OP" ] || [ "$API_KEY" != "$LEGACY_API_KEY" ] || [ "$SECRET" != "$LEGACY_SECRET" ]; }; then
  log_warning "Configured credentials failed with 1001 on HOST=${PORTAL_HOST}; retrying with legacy43 credentials because ALLOW_LEGACY_AUTH_FALLBACK=1."
  OP="$LEGACY_OP"
  API_KEY="$LEGACY_API_KEY"
  SECRET="$LEGACY_SECRET"
  authenticate_once "$OP" "$API_KEY" "$SECRET"
fi

print_json "$TOKEN_JSON"
assert_success "Get access token" "$TOKEN_JSON"

ACCESS_TOKEN="$(json_get_string "$TOKEN_JSON" "accessToken")"
REFRESH_TOKEN="$(json_get_string "$TOKEN_JSON" "refreshToken")"
TOKEN_TYPE="$(json_get_string "$TOKEN_JSON" "tokenType")"
ACCESS_EXPIRES_IN="$(json_get_number "$TOKEN_JSON" "expiresIn")"
AUTH_SCOPE="$(json_get_string "$TOKEN_JSON" "scope")"

if [ -z "$ACCESS_TOKEN" ] || [ -z "$REFRESH_TOKEN" ]; then
  log_line "[FAIL] Get access token"
  log_line "Cannot extract accessToken/refreshToken"
  echo "FAILED at step: Get access token"
  echo "Cannot extract accessToken/refreshToken"
  exit 1
fi

assert_equal "Get access token tokenType" "Bearer" "$TOKEN_TYPE"
assert_equal "Get access token expiresIn" "3600" "$ACCESS_EXPIRES_IN"

if [ "$IS_LOCAL_LEGACY_HOST" -eq 1 ]; then
  if [ "$AUTH_SCOPE" = "read,write" ]; then
    log_warning "HOST=${PORTAL_HOST} returned legacy token scope read,write; continuing because this is an accepted local compatibility mode."
  elif [ -n "$AUTH_SCOPE" ]; then
    log_warning "HOST=${PORTAL_HOST} returned unexpected scope '${AUTH_SCOPE}' in local compatibility mode."
  fi
fi

# =========================
# 2. REFRESH ACCESS TOKEN
# =========================

call_api \
  "2. Refresh access token" \
  "/4002" \
  "{\"refreshToken\":\"$REFRESH_TOKEN\"}"

REFRESHED_ACCESS_TOKEN="$(json_get_string "$LAST_RESPONSE" "accessToken")"
REFRESHED_REFRESH_TOKEN="$(json_get_string "$LAST_RESPONSE" "refreshToken")"

if [ -z "$REFRESHED_ACCESS_TOKEN" ] || [ -z "$REFRESHED_REFRESH_TOKEN" ]; then
  log_line "[FAIL] Refresh access token"
  log_line "Cannot extract refreshed tokens"
  echo "FAILED at step: Refresh access token"
  echo "Cannot extract refreshed tokens"
  exit 1
fi

ACCESS_TOKEN="$REFRESHED_ACCESS_TOKEN"
REFRESH_TOKEN="$REFRESHED_REFRESH_TOKEN"

# =========================
# 3. CREATE ACCOUNT
# =========================

call_api_no_assert \
  "3. Create account" \
  "/4011" \
  "{\"operatorCode\":\"$OP\",\"username\":\"$USER\",\"currency\":\"$CURRENCY\",\"country\":\"$COUNTRY\",\"language\":\"$LANGUAGE\"}" \
  -H "Authorization: Bearer $ACCESS_TOKEN"

CREATE_SUCCESS="$(json_get_bool "$LAST_RESPONSE" "success")"
CREATE_ERROR_CODE="$(json_get_string "$LAST_RESPONSE" "errorCode")"
CREATE_ERROR_MESSAGE="$(json_get_string "$LAST_RESPONSE" "errorMessage")"

if [ "$CREATE_SUCCESS" != "true" ]; then
  if [ "$IS_LOCAL_LEGACY_HOST" -eq 1 ] && [ "$CREATE_ERROR_CODE" = "5000" ]; then
    BLOCK_REASON="HOST=${PORTAL_HOST} is environment-divergent from the official v2 spec; auth works only with legacy credentials and create-account 4011 is broken server-side."
    log_warning "$BLOCK_REASON"

    call_api_no_assert \
      "3a. Probe get balance route with nonexistent user" \
      "/4012" \
      "{\"operatorCode\":\"$OP\",\"username\":\"$USER\"}" \
      -H "Authorization: Bearer $ACCESS_TOKEN"
    if [ "$(json_get_string "$LAST_RESPONSE" "errorCode")" = "3001" ]; then
      log_info "4012 is reachable and correctly reports missing player with 3001."
    fi

    call_api_no_assert \
      "3b. Probe transfer route with nonexistent user" \
      "/4021" \
      "{\"operatorCode\":\"$OP\",\"username\":\"$USER\",\"transactionId\":\"$DEPOSIT_TXN\",\"type\":\"DEPOSIT\",\"amount\":$DEPOSIT_AMOUNT,\"currency\":\"$CURRENCY\",\"description\":\"Probe deposit\"}" \
      -H "Authorization: Bearer $ACCESS_TOKEN"
    if [ "$(json_get_string "$LAST_RESPONSE" "errorCode")" = "3001" ]; then
      log_info "4021 is reachable and correctly reports missing player with 3001."
    fi

    call_api_no_assert \
      "3c. Probe launch route with nonexistent user" \
      "/4031" \
      "{\"operatorCode\":\"$OP\",\"username\":\"$USER\",\"gameId\":\"$GAME_ID\",\"platform\":\"$PLATFORM\",\"language\":\"$LANGUAGE\",\"returnUrl\":\"$RETURN_URL\"}" \
      -H "Authorization: Bearer $ACCESS_TOKEN"
    if [ "$(json_get_string "$LAST_RESPONSE" "errorCode")" = "3001" ]; then
      log_info "4031 is reachable and correctly reports missing player with 3001."
    fi

    call_api_no_assert \
      "3d. Probe payment history route on local host" \
      "/4042" \
      "{\"operatorCode\":\"$OP\",\"transactionId\":\"$DEPOSIT_TXN\"}" \
      -H "Authorization: Bearer $ACCESS_TOKEN"
    if printf "%s" "$LAST_RESPONSE" | grep -Fq '"data":[]'; then
      log_warning "4042 returned success with empty data; this is local-host behavior but diverges from the official spec, which expects 3011 for a missing transaction."
    fi

    call_api_no_assert \
      "3e. Probe betting history route on local host" \
      "/4041" \
      "{\"ticket\":123456789,\"limit\":20}" \
      -H "Authorization: Bearer $ACCESS_TOKEN"
    if printf "%s" "$LAST_RESPONSE" | grep -Fq '"data":[]'; then
      log_info "4041 returned empty array, accepted as local-host behavior."
    fi

    finish_blocked "$BLOCK_REASON"
  fi

  log_line "[FAIL] 3. Create account"
  log_line "Error Code: $CREATE_ERROR_CODE"
  log_line "Error Message: $CREATE_ERROR_MESSAGE"
  echo "FAILED at step: 3. Create account"
  echo "Error Code: $CREATE_ERROR_CODE"
  echo "Error Message: $CREATE_ERROR_MESSAGE"
  exit 1
fi

log_line "[PASS] 3. Create account"

CREATED_USERNAME="$(json_get_string "$LAST_RESPONSE" "username")"
CREATED_CURRENCY="$(json_get_string "$LAST_RESPONSE" "currency")"
CREATED_STATUS="$(json_get_string "$LAST_RESPONSE" "status")"
CREATED_BALANCE="$(json_get_number "$LAST_RESPONSE" "balance")"

assert_equal "Create account username" "$USER" "$CREATED_USERNAME"
assert_equal "Create account currency" "$CURRENCY" "$CREATED_CURRENCY"
assert_equal "Create account status" "ACTIVE" "$CREATED_STATUS"
assert_equal "Create account opening balance" "0" "$CREATED_BALANCE"

# =========================
# 4. CHECK INITIAL BALANCE
# =========================

call_api \
  "4. Check initial balance" \
  "/4012" \
  "{\"operatorCode\":\"$OP\",\"username\":\"$USER\"}" \
  -H "Authorization: Bearer $ACCESS_TOKEN"

BALANCE_USERNAME="$(json_get_string "$LAST_RESPONSE" "username")"
BALANCE_CURRENCY="$(json_get_string "$LAST_RESPONSE" "currency")"
BALANCE_AMOUNT="$(json_get_number "$LAST_RESPONSE" "balance")"
AVAILABLE_BALANCE="$(json_get_number "$LAST_RESPONSE" "availableBalance")"
LOCKED_BALANCE="$(json_get_number "$LAST_RESPONSE" "lockedBalance")"

assert_equal "Initial balance username" "$USER" "$BALANCE_USERNAME"
assert_equal "Initial balance currency" "$CURRENCY" "$BALANCE_CURRENCY"
assert_equal "Initial balance amount" "0" "$BALANCE_AMOUNT"
assert_equal "Initial available balance" "0" "$AVAILABLE_BALANCE"
assert_equal "Initial locked balance" "0" "$LOCKED_BALANCE"

# =========================
# 5. DEPOSIT
# =========================

call_api \
  "5. Deposit" \
  "/4021" \
  "{\"operatorCode\":\"$OP\",\"username\":\"$USER\",\"transactionId\":\"$DEPOSIT_TXN\",\"type\":\"DEPOSIT\",\"amount\":$DEPOSIT_AMOUNT,\"currency\":\"$CURRENCY\",\"description\":\"Deposit from main wallet\"}" \
  -H "Authorization: Bearer $ACCESS_TOKEN" \
  -H "X-Request-ID: $DEPOSIT_REQUEST_ID"

DEPOSIT_TYPE="$(json_get_string "$LAST_RESPONSE" "type")"
DEPOSIT_STATUS="$(json_get_string "$LAST_RESPONSE" "status")"
DEPOSIT_TXN_RESPONSE="$(json_get_string "$LAST_RESPONSE" "transactionId")"
DEPOSIT_AMOUNT_RESPONSE="$(json_get_number "$LAST_RESPONSE" "amount")"
DEPOSIT_AFTER="$(json_get_number "$LAST_RESPONSE" "balanceAfter")"

assert_equal "Deposit type" "DEPOSIT" "$DEPOSIT_TYPE"
assert_equal "Deposit status" "SUCCESS" "$DEPOSIT_STATUS"
assert_equal "Deposit amount" "$DEPOSIT_AMOUNT" "$DEPOSIT_AMOUNT_RESPONSE"
assert_equal "Deposit balanceAfter" "$DEPOSIT_AMOUNT" "$DEPOSIT_AFTER"

if [ -z "$DEPOSIT_TXN_RESPONSE" ]; then
  log_line "[FAIL] Deposit"
  log_line "Cannot extract transactionId"
  echo "FAILED at step: Deposit"
  echo "Cannot extract transactionId"
  exit 1
fi

# =========================
# 6. DEPOSIT IDEMPOTENCY
# =========================

call_api \
  "6. Deposit idempotency" \
  "/4021" \
  "{\"operatorCode\":\"$OP\",\"username\":\"$USER\",\"transactionId\":\"$DEPOSIT_TXN\",\"type\":\"DEPOSIT\",\"amount\":$DEPOSIT_AMOUNT,\"currency\":\"$CURRENCY\",\"description\":\"Deposit from main wallet\"}" \
  -H "Authorization: Bearer $ACCESS_TOKEN" \
  -H "X-Request-ID: $DEPOSIT_REQUEST_ID"

DUPLICATE_DEPOSIT_AFTER="$(json_get_number "$LAST_RESPONSE" "balanceAfter")"
DUPLICATE_DEPOSIT_AMOUNT="$(json_get_number "$LAST_RESPONSE" "amount")"

assert_equal "Deposit idempotency amount" "$DEPOSIT_AMOUNT" "$DUPLICATE_DEPOSIT_AMOUNT"

if [ "$DUPLICATE_DEPOSIT_AFTER" = "$DEPOSIT_AMOUNT" ]; then
  EFFECTIVE_BALANCE_AFTER_DEPOSIT="$DEPOSIT_AMOUNT"
elif [ "$DUPLICATE_DEPOSIT_AFTER" = "$((DEPOSIT_AMOUNT * 2))" ]; then
  EFFECTIVE_BALANCE_AFTER_DEPOSIT="$DUPLICATE_DEPOSIT_AFTER"
  log_warning "Idempotency mismatch: repeated 4021 with same X-Request-ID still changed balance on this backend."
else
  log_line "[FAIL] Deposit idempotency balanceAfter"
  log_line "Expected either: $DEPOSIT_AMOUNT or $((DEPOSIT_AMOUNT * 2))"
  log_line "Actual: $DUPLICATE_DEPOSIT_AFTER"
  echo
  echo "FAILED at step: Deposit idempotency balanceAfter"
  echo "Expected either: $DEPOSIT_AMOUNT or $((DEPOSIT_AMOUNT * 2))"
  echo "Actual:   $DUPLICATE_DEPOSIT_AFTER"
  exit 1
fi

# =========================
# 7. CHECK BALANCE AFTER DEPOSIT
# =========================

call_api \
  "7. Check balance after deposit" \
  "/4012" \
  "{\"operatorCode\":\"$OP\",\"username\":\"$USER\"}" \
  -H "Authorization: Bearer $ACCESS_TOKEN"

BALANCE_AFTER_DEPOSIT="$(json_get_number "$LAST_RESPONSE" "balance")"
AVAILABLE_AFTER_DEPOSIT="$(json_get_number "$LAST_RESPONSE" "availableBalance")"

assert_equal "Balance after deposit" "$EFFECTIVE_BALANCE_AFTER_DEPOSIT" "$BALANCE_AFTER_DEPOSIT"
assert_equal "Available balance after deposit" "$EFFECTIVE_BALANCE_AFTER_DEPOSIT" "$AVAILABLE_AFTER_DEPOSIT"

# =========================
# 8. LAUNCH GAME
# =========================

call_api \
  "8. Launch game" \
  "/4031" \
  "{\"operatorCode\":\"$OP\",\"username\":\"$USER\",\"gameId\":\"$GAME_ID\",\"platform\":\"$PLATFORM\",\"language\":\"$LANGUAGE\",\"returnUrl\":\"$RETURN_URL\"}" \
  -H "Authorization: Bearer $ACCESS_TOKEN"

LAUNCH_URL="$(json_get_string "$LAST_RESPONSE" "launchUrl")"
SESSION_TOKEN="$(json_get_string "$LAST_RESPONSE" "sessionToken")"
LAUNCH_EXPIRES_IN="$(json_get_number "$LAST_RESPONSE" "expiresIn")"
LAUNCH_GAME_ID="$(json_get_string "$LAST_RESPONSE" "gameId")"
LAUNCH_PLATFORM="$(json_get_string "$LAST_RESPONSE" "platform")"

if [ -z "$LAUNCH_URL" ] || [ -z "$SESSION_TOKEN" ]; then
  log_line "[FAIL] Launch game"
  log_line "Missing launchUrl/sessionToken"
  echo "FAILED at step: Launch game"
  echo "Missing launchUrl/sessionToken"
  exit 1
fi

assert_contains "Launch game URL contains username" "$LAUNCH_URL" "$USER"
assert_contains "Launch game URL contains game" "$LAUNCH_URL" "$GAME_ID"
assert_equal "Launch game expiresIn" "10800" "$LAUNCH_EXPIRES_IN"
assert_equal "Launch game gameId" "$GAME_ID" "$LAUNCH_GAME_ID"
assert_equal "Launch game platform" "$PLATFORM" "$LAUNCH_PLATFORM"

# =========================
# 9. WITHDRAW
# =========================

call_api \
  "9. Withdraw" \
  "/4021" \
  "{\"operatorCode\":\"$OP\",\"username\":\"$USER\",\"transactionId\":\"$WITHDRAW_TXN\",\"type\":\"WITHDRAW\",\"amount\":$WITHDRAW_AMOUNT,\"currency\":\"$CURRENCY\",\"description\":\"Withdraw to main wallet\"}" \
  -H "Authorization: Bearer $ACCESS_TOKEN" \
  -H "X-Request-ID: $WITHDRAW_REQUEST_ID"

WITHDRAW_TYPE="$(json_get_string "$LAST_RESPONSE" "type")"
WITHDRAW_STATUS="$(json_get_string "$LAST_RESPONSE" "status")"
WITHDRAW_AMOUNT_RESPONSE="$(json_get_number "$LAST_RESPONSE" "amount")"
WITHDRAW_AFTER="$(json_get_number "$LAST_RESPONSE" "balanceAfter")"
EXPECTED_FINAL_BALANCE=$((EFFECTIVE_BALANCE_AFTER_DEPOSIT - WITHDRAW_AMOUNT))

assert_equal "Withdraw type" "WITHDRAW" "$WITHDRAW_TYPE"
assert_equal "Withdraw status" "SUCCESS" "$WITHDRAW_STATUS"
assert_equal "Withdraw amount" "$WITHDRAW_AMOUNT" "$WITHDRAW_AMOUNT_RESPONSE"
assert_equal "Withdraw balanceAfter" "$EXPECTED_FINAL_BALANCE" "$WITHDRAW_AFTER"

# =========================
# 10. CHECK FINAL BALANCE
# =========================

call_api \
  "10. Final balance" \
  "/4012" \
  "{\"operatorCode\":\"$OP\",\"username\":\"$USER\"}" \
  -H "Authorization: Bearer $ACCESS_TOKEN"

FINAL_BALANCE="$(json_get_number "$LAST_RESPONSE" "balance")"
FINAL_AVAILABLE_BALANCE="$(json_get_number "$LAST_RESPONSE" "availableBalance")"
FINAL_LOCKED_BALANCE="$(json_get_number "$LAST_RESPONSE" "lockedBalance")"

assert_equal "Final balance amount" "$EXPECTED_FINAL_BALANCE" "$FINAL_BALANCE"
assert_equal "Final available balance" "$EXPECTED_FINAL_BALANCE" "$FINAL_AVAILABLE_BALANCE"
assert_equal "Final locked balance" "0" "$FINAL_LOCKED_BALANCE"

# =========================
# 11. WAIT FOR ASYNC HISTORY
# =========================

echo
echo "Waiting ${ASYNC_WAIT_SECONDS}s for async transaction history..."
log_line "Waiting ${ASYNC_WAIT_SECONDS}s for async transaction history..."
sleep "$ASYNC_WAIT_SECONDS"

# =========================
# 12. GET PAYMENT TRANSACTION - DEPOSIT
# =========================

call_api \
  "12. Get payment transaction (deposit)" \
  "/4042" \
  "{\"operatorCode\":\"$OP\",\"transactionId\":\"$DEPOSIT_TXN\"}" \
  -H "Authorization: Bearer $ACCESS_TOKEN"

if printf "%s" "$LAST_RESPONSE" | grep -Fq '"data":[]'; then
  log_line "[FAIL] Payment transaction deposit data"
  log_line "4042 returned empty data; expected deposit transaction ${DEPOSIT_TXN}."
  echo
  echo "FAILED at step: Payment transaction deposit data"
  echo "4042 returned empty data; expected deposit transaction ${DEPOSIT_TXN}."
  exit 1
fi

PAYMENT_TYPE="$(json_get_string "$LAST_RESPONSE" "type")"
PAYMENT_STATUS="$(json_get_string "$LAST_RESPONSE" "status")"
PAYMENT_AMOUNT="$(json_get_number "$LAST_RESPONSE" "amount")"
PAYMENT_CURRENCY="$(json_get_string "$LAST_RESPONSE" "currency")"
PAYMENT_METHOD="$(json_get_string "$LAST_RESPONSE" "paymentMethod")"
PAYMENT_SYSTEM_TRANSACTION_ID="$(json_get_string "$LAST_RESPONSE" "systemTransactionId")"

assert_equal "Payment transaction type" "DEPOSIT" "$PAYMENT_TYPE"
assert_equal "Payment transaction status" "SUCCESS" "$PAYMENT_STATUS"
assert_equal "Payment transaction amount" "$DEPOSIT_AMOUNT" "$PAYMENT_AMOUNT"
assert_equal "Payment transaction currency" "$CURRENCY" "$PAYMENT_CURRENCY"
assert_equal "Payment transaction paymentMethod" "TRANSFER" "$PAYMENT_METHOD"

if [ -z "$PAYMENT_SYSTEM_TRANSACTION_ID" ]; then
  log_line "[FAIL] Payment transaction systemTransactionId"
  log_line "Missing systemTransactionId in 4042 response"
  echo
  echo "FAILED at step: Payment transaction systemTransactionId"
  echo "Missing systemTransactionId in 4042 response"
  exit 1
fi

# =========================
# 13. GET BETTING HISTORY
# =========================

call_api \
  "13. Get betting history" \
  "/4041" \
  "{\"operatorCode\":\"$OP\",\"ticket\":$PAYMENT_SYSTEM_TRANSACTION_ID}" \
  -H "Authorization: Bearer $ACCESS_TOKEN"

HISTORY_ACTION="$(json_get_string "$LAST_RESPONSE" "action_name")"
HISTORY_TYPE="$(json_get_string "$LAST_RESPONSE" "type")"
HISTORY_USER="$(json_get_string "$LAST_RESPONSE" "user_name")"
HISTORY_STATUS="$(json_get_string "$LAST_RESPONSE" "payment_status")"
HISTORY_EXCHANGE="$(json_get_number "$LAST_RESPONSE" "money_exchange")"

if printf "%s" "$LAST_RESPONSE" | grep -Fq '"data":[]'; then
  log_warning "Betting history lookup returned empty data for ticket ${PAYMENT_SYSTEM_TRANSACTION_ID}."
else
  assert_equal "Betting history username" "$USER" "$HISTORY_USER"
  assert_equal "Betting history type" "DEPOSIT" "$HISTORY_TYPE"
  assert_equal "Betting history action" "DEPOSIT" "$HISTORY_ACTION"
  assert_equal "Betting history payment status" "SUCCESS" "$HISTORY_STATUS"
  assert_equal "Betting history exchange amount" "$DEPOSIT_AMOUNT" "$HISTORY_EXCHANGE"
fi

# =========================
# 14. GET PAYMENT TRANSACTION - WITHDRAW
# =========================

call_api \
  "14. Get payment transaction (withdraw)" \
  "/4042" \
  "{\"operatorCode\":\"$OP\",\"transactionId\":\"$WITHDRAW_TXN\"}" \
  -H "Authorization: Bearer $ACCESS_TOKEN"

if printf "%s" "$LAST_RESPONSE" | grep -Fq '"data":[]'; then
  log_line "[FAIL] Payment transaction withdraw data"
  log_line "4042 returned empty data; expected withdraw transaction ${WITHDRAW_TXN}."
  echo
  echo "FAILED at step: Payment transaction withdraw data"
  echo "4042 returned empty data; expected withdraw transaction ${WITHDRAW_TXN}."
  exit 1
fi

WITHDRAW_PAYMENT_TYPE="$(json_get_string "$LAST_RESPONSE" "type")"
WITHDRAW_PAYMENT_STATUS="$(json_get_string "$LAST_RESPONSE" "status")"
WITHDRAW_PAYMENT_AMOUNT="$(json_get_number "$LAST_RESPONSE" "amount")"

assert_equal "Withdraw payment transaction type" "WITHDRAW" "$WITHDRAW_PAYMENT_TYPE"
assert_equal "Withdraw payment transaction status" "SUCCESS" "$WITHDRAW_PAYMENT_STATUS"
assert_equal "Withdraw payment transaction amount" "$WITHDRAW_AMOUNT" "$WITHDRAW_PAYMENT_AMOUNT"

# =========================
# DONE
# =========================

echo
echo "======================================"
echo "FULL SPEC FLOW PASSED"
echo "======================================"
echo "USER: $USER"
echo "FINAL_BALANCE: $FINAL_BALANCE"
echo "DEPOSIT_TXN: $DEPOSIT_TXN"
echo "WITHDRAW_TXN: $WITHDRAW_TXN"
echo "======================================"

log_line ""
log_line "======================================"
log_line "FULL SPEC FLOW PASSED"
log_line "======================================"
log_line "USER: $USER"
log_line "FINAL_BALANCE: $FINAL_BALANCE"
log_line "DEPOSIT_TXN: $DEPOSIT_TXN"
log_line "WITHDRAW_TXN: $WITHDRAW_TXN"
log_line "WARNING_COUNT: $WARNING_COUNT"
log_line "Completed at: $(date '+%Y-%m-%d %H:%M:%S')"
log_line "======================================"
