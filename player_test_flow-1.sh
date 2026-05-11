#!/usr/bin/env bash

set -o pipefail

ENV_FILE="${ENV_FILE:-.env}"
LOADED_ENV_FILE=""

load_env_file() {
  local file="$1"
  local line
  local key
  local value

  if [ ! -f "$file" ]; then
    return 0
  fi

  while IFS= read -r line || [ -n "$line" ]; do
    line="${line%$'\r'}"
    case "$line" in
      ""|\#*) continue ;;
    esac

    key="${line%%=*}"
    value="${line#*=}"

    if ! printf "%s" "$key" | grep -Eq '^[A-Za-z_][A-Za-z0-9_]*$'; then
      continue
    fi

    if [ "${value#\"}" != "$value" ] && [ "${value%\"}" != "$value" ]; then
      value="${value#\"}"
      value="${value%\"}"
    elif [ "${value#\'}" != "$value" ] && [ "${value%\'}" != "$value" ]; then
      value="${value#\'}"
      value="${value%\'}"
    fi

    if [ -z "${!key+x}" ]; then
      export "$key=$value"
    fi
  done < "$file"

  LOADED_ENV_FILE="$file"
}

load_env_file "$ENV_FILE"

trim_trailing_slash() {
  local value="$1"
  while [ "${value%/}" != "$value" ]; do
    value="${value%/}"
  done
  printf "%s" "$value"
}

HOST="${HOST:-127.0.0.1}"
PORTAL_SCHEME="${PORTAL_SCHEME:-http}"
PORTAL_HOST="${PORTAL_HOST:-${HOST}}"
PORTAL_PORT="${PORTAL_PORT:-8081}"
PORTAL_PATH="${PORTAL_PATH:-/api}"
PORTAL_BASE_URL="${PORTAL_BASE_URL:-${PORTAL_SCHEME}://${PORTAL_HOST}:${PORTAL_PORT}}"
PORTAL_URL="${PORTAL_URL:-$(trim_trailing_slash "$PORTAL_BASE_URL")$PORTAL_PATH}"
CURL_TIMEOUT="${CURL_TIMEOUT:-30}"

RUN_SUFFIX="${RUN_SUFFIX:-$(date +%s)}"
SHORT_SUFFIX="$(printf "%s" "$RUN_SUFFIX" | tail -c 7)"
USERNAME="${USERNAME:-test${SHORT_SUFFIX}}"
PASSWORD="${PASSWORD:-123456}"
NICKNAME="${NICKNAME:-play_${SHORT_SUFFIX}}"
DEVICE_ID="${DEVICE_ID:-player-flow-${SHORT_SUFFIX}}"

MONEY_TYPE="${MONEY_TYPE:-1}"
PAGE="${PAGE:-1}"
TODAY="${TODAY:-$(date +%F)}"
MONTH="${MONTH:-$(date +%Y-%m)}"
DAY_NUM="${DAY_NUM:-$(date +%d)}"
MONTH_NUM="${MONTH_NUM:-$(date +%m)}"
YEAR_NUM="${YEAR_NUM:-$(date +%Y)}"

SKIP_REGISTER="${SKIP_REGISTER:-0}"
ENABLE_MUTATION_PROBES="${ENABLE_MUTATION_PROBES:-0}"
ENABLE_EXTERNAL_PAYMENT_PROBES="${ENABLE_EXTERNAL_PAYMENT_PROBES:-0}"

CAPTCHA_FILE="${CAPTCHA_FILE:-captcha.png}"
LOG_DIR="${LOG_DIR:-logs}"
LOG_FILE="${LOG_FILE:-${LOG_DIR}/player_test_flow_${USERNAME}.log}"
LOG_TO_STDOUT="${LOG_TO_STDOUT:-0}"

PASS_COUNT=0
WARN_COUNT=0
FAIL_COUNT=0
LAST_RESPONSE=""
SESSION_KEY=""
ACCESS_TOKEN=""
LOGIN_PASSWORD="$PASSWORD"
API_CALL_COUNT=0
LAST_HTTP_CODE=""
LAST_CURL_RC=0
LAST_CURL_TIME=""
LAST_CURL_EFFECTIVE_URL=""
LAST_CURL_STDERR=""

setup_logging() {
  mkdir -p "$LOG_DIR"
  : > "$LOG_FILE"

  if [ "$LOG_TO_STDOUT" = "1" ] && [ -n "${BASH_VERSION:-}" ]; then
    exec > >(tee -a "$LOG_FILE") 2>&1
    return 0
  fi

  exec >>"$LOG_FILE" 2>&1
}

setup_logging

print_header() {
  local title="$1"
  echo ""
  echo "=============================="
  echo "$title"
  echo "=============================="
}

mark_pass() {
  PASS_COUNT=$((PASS_COUNT + 1))
  echo "[PASS] $1"
}

mark_warn() {
  WARN_COUNT=$((WARN_COUNT + 1))
  echo "[WARN] $1"
}

mark_fail() {
  FAIL_COUNT=$((FAIL_COUNT + 1))
  echo "[FAIL] $1"
}

mark_skip() {
  echo "[SKIP] $1"
}

require_tool() {
  local name="$1"
  if ! command -v "$name" >/dev/null 2>&1; then
    echo "ERROR: missing required tool: $name"
    exit 1
  fi
}

json_get() {
  local json="$1"
  local filter="$2"
  printf "%s" "$json" | jq -r "$filter // empty" 2>/dev/null || true
}

is_json() {
  printf "%s" "$1" | jq -e . >/dev/null 2>&1
}

masked_param() {
  local param="$1"
  local key="${param%%=*}"
  case "$key" in
    pw|cp|otp|at|apiKey|secretKey|sessionKey)
      printf "%s=***" "$key"
      ;;
    *)
      printf "%s" "$param"
      ;;
  esac
}

log_params() {
  local label="$1"
  shift

  printf "%s" "$label"
  if [ "$#" -eq 0 ]; then
    printf " (none)\n"
    return 0
  fi

  local param
  for param in "$@"; do
    printf " "
    masked_param "$param"
  done
  printf "\n"
}

run_curl_request() {
  local step="$1"
  local method="$2"
  local url="$3"
  shift 3

  local body_file
  local err_file
  local meta_file
  body_file="$(mktemp)"
  err_file="$(mktemp)"
  meta_file="$(mktemp)"

  API_CALL_COUNT=$((API_CALL_COUNT + 1))

  echo ""
  echo "[API $API_CALL_COUNT] $(date '+%Y-%m-%d %H:%M:%S %Z')"
  echo "Step   : $step"
  echo "Method : $method"
  echo "URL    : $url"
  log_params "Params :" "$@"

  curl \
    -sS \
    --max-time "$CURL_TIMEOUT" \
    -o "$body_file" \
    -w 'http_code=%{http_code}\ntime_total=%{time_total}\nurl_effective=%{url_effective}\n' \
    "${CURL_ARGS[@]}" >"$meta_file" 2>"$err_file"
  LAST_CURL_RC=$?
  LAST_RESPONSE="$(cat "$body_file")"
  LAST_CURL_STDERR="$(cat "$err_file")"
  LAST_HTTP_CODE="$(awk -F= '/^http_code=/{print $2}' "$meta_file")"
  LAST_CURL_TIME="$(awk -F= '/^time_total=/{print $2}' "$meta_file")"
  LAST_CURL_EFFECTIVE_URL="$(awk -F= '/^url_effective=/{print $2}' "$meta_file")"

  echo "Curl rc: ${LAST_CURL_RC}"
  echo "HTTP   : ${LAST_HTTP_CODE:-n/a}"
  echo "Time   : ${LAST_CURL_TIME:-n/a}s"
  echo "Final  : ${LAST_CURL_EFFECTIVE_URL:-$url}"
  if [ -n "$LAST_CURL_STDERR" ]; then
    echo "stderr :"
    printf "%s\n" "$LAST_CURL_STDERR"
  fi
  echo "Body   :"
  printf "%s\n" "$LAST_RESPONSE"

  rm -f "$body_file" "$err_file" "$meta_file"
  return "$LAST_CURL_RC"
}

md5_text() {
  local text="$1"

  if command -v md5sum >/dev/null 2>&1; then
    printf "%s" "$text" | md5sum | awk '{print $1}'
    return 0
  fi

  if command -v md5 >/dev/null 2>&1; then
    printf "%s" "$text" | md5 | awk '{print $NF}'
    return 0
  fi

  if command -v openssl >/dev/null 2>&1; then
    printf "%s" "$text" | openssl md5 | awk '{print $NF}'
    return 0
  fi

  return 1
}

decode_base64_file() {
  local input="$1"
  local output="$2"

  if base64 --help 2>&1 | grep -q -- "--decode"; then
    printf "%s" "$input" | base64 --decode > "$output"
    return $?
  fi

  printf "%s" "$input" | base64 -D > "$output"
}

legacy_get() {
  local step="$1"
  shift

  CURL_ARGS=(-sS --max-time "$CURL_TIMEOUT" --get "$PORTAL_URL")
  local param
  for param in "$@"; do
    CURL_ARGS+=(--data-urlencode "$param")
  done

  run_curl_request "$step" "GET" "$PORTAL_URL" "$@"
}

response_success() {
  local success
  local error_code

  success="$(json_get "$LAST_RESPONSE" ".success")"
  error_code="$(json_get "$LAST_RESPONSE" ".errorCode")"

  [ "$success" = "true" ] || [ "$error_code" = "0" ]
}

response_error_code() {
  json_get "$LAST_RESPONSE" ".errorCode"
}

require_success_or_allowed() {
  local step="$1"
  shift

  local error_code
  error_code="$(response_error_code)"

  if response_success; then
    mark_pass "$step"
    return 0
  fi

  local allowed
  for allowed in "$@"; do
    if [ "$error_code" = "$allowed" ]; then
      mark_pass "$step accepted expected errorCode=$error_code"
      return 0
    fi
  done

  mark_fail "$step failed, errorCode=${error_code:-non-json}"
  exit 1
}

require_nonempty_response() {
  local step="$1"

  if [ -n "$LAST_RESPONSE" ]; then
    mark_pass "$step"
    return 0
  fi

  mark_fail "$step returned empty response"
  exit 1
}

require_json_response() {
  local step="$1"

  if is_json "$LAST_RESPONSE"; then
    mark_pass "$step returned JSON"
    return 0
  fi

  mark_fail "$step did not return JSON"
  exit 1
}

probe_call() {
  local step="$1"
  shift

  if ! legacy_get "$step" "$@"; then
    mark_warn "$step curl failed"
    return 0
  fi

  if response_success; then
    mark_pass "$step"
    return 0
  fi

  if is_json "$LAST_RESPONSE"; then
    local error_code
    error_code="$(response_error_code)"
    mark_warn "$step returned errorCode=${error_code:-no-error-code}"
    return 0
  fi

  if [ -n "$LAST_RESPONSE" ]; then
    mark_pass "$step returned non-empty non-standard response"
    return 0
  fi

  mark_warn "$step returned empty response"
}

probe_json_or_nonempty() {
  local step="$1"
  shift

  if ! legacy_get "$step" "$@"; then
    mark_warn "$step curl failed"
    return 0
  fi

  if is_json "$LAST_RESPONSE"; then
    mark_pass "$step returned JSON"
    return 0
  fi

  if [ -n "$LAST_RESPONSE" ]; then
    mark_pass "$step returned non-empty response"
    return 0
  fi

  mark_warn "$step returned empty response"
}

extract_login_fields() {
  SESSION_KEY="$(json_get "$LAST_RESPONSE" ".sessionKey")"
  ACCESS_TOKEN="$(json_get "$LAST_RESPONSE" ".accessToken")"

  local response_nickname
  response_nickname="$(json_get "$LAST_RESPONSE" ".nickname")"
  if [ -n "$response_nickname" ]; then
    NICKNAME="$response_nickname"
  fi
}

login_with_password() {
  local password="$1"
  legacy_get "Login legacy player (c=3)" "c=3" "un=$USERNAME" "pw=$password"
  extract_login_fields
}

print_header "LEGACY PLAYER API FULL FLOW"
echo "Started at : $(date '+%Y-%m-%d %H:%M:%S %Z')"
echo "Env file   : ${LOADED_ENV_FILE:-not loaded}"
echo "Portal URL : $PORTAL_URL"
echo "Username   : $USERNAME"
echo "Nickname   : $NICKNAME"
echo "Log file   : $LOG_FILE"
echo ""
echo "Flags:"
echo "  SKIP_REGISTER=$SKIP_REGISTER"
echo "  ENABLE_MUTATION_PROBES=$ENABLE_MUTATION_PROBES"
echo "  ENABLE_EXTERNAL_PAYMENT_PROBES=$ENABLE_EXTERNAL_PAYMENT_PROBES"

print_header "0. Preflight"
require_tool curl
require_tool jq
mark_pass "Required tools found"

if ! legacy_get "Server time (c=9)" "c=9"; then
  mark_fail "Server time (c=9) curl failed"
  exit 1
fi
require_nonempty_response "Server time (c=9)"

if [ "$SKIP_REGISTER" != "1" ]; then
  print_header "1. Register Player"
  if ! legacy_get "Get captcha (c=124)" "c=124"; then
    mark_fail "Get captcha (c=124) curl failed"
    exit 1
  fi
  require_json_response "Get captcha (c=124)"

  CID="$(json_get "$LAST_RESPONSE" ".id")"
  IMG="$(json_get "$LAST_RESPONSE" ".img")"

  if [ -z "$CID" ] || [ -z "$IMG" ]; then
    mark_fail "Captcha response missing id/img"
    exit 1
  fi

  if ! decode_base64_file "$IMG" "$CAPTCHA_FILE"; then
    mark_fail "Cannot decode captcha image"
    exit 1
  fi

  echo "Captcha ID: $CID"
  echo "Saved captcha image: $CAPTCHA_FILE"

  if [ -z "${CAPTCHA:-}" ]; then
    if command -v open >/dev/null 2>&1; then
      open "$CAPTCHA_FILE" >/dev/null 2>&1 || true
    elif command -v xdg-open >/dev/null 2>&1; then
      xdg-open "$CAPTCHA_FILE" >/dev/null 2>&1 || true
    fi

    echo ""
    read -r -p "Enter captcha: " CAPTCHA
  fi

  if [ -z "${CAPTCHA:-}" ]; then
    mark_fail "Captcha is empty"
    exit 1
  fi

  if ! legacy_get "Quick register (c=1)" \
    "c=1" \
    "un=$USERNAME" \
    "pw=$PASSWORD" \
    "cp=$CAPTCHA" \
    "cid=$CID" \
    "utm_source=player_test_flow" \
    "utm_medium=script" \
    "utm_campaign=legacy_full_flow"; then
    mark_fail "Quick register (c=1) curl failed"
    exit 1
  fi
  require_success_or_allowed "Quick register (c=1)" "1006"
else
  print_header "1. Register Player"
  mark_warn "SKIP_REGISTER=1, using existing USERNAME/PASSWORD"
fi

print_header "2. Login And Session"
login_with_password "$LOGIN_PASSWORD"
LOGIN_ERROR_CODE="$(response_error_code)"

if response_success && [ -n "$SESSION_KEY" ]; then
  mark_pass "Login legacy player (c=3)"
elif [ "$LOGIN_ERROR_CODE" = "2001" ]; then
  mark_warn "Login requires nickname setup, continue with c=5"
elif [ "$LOGIN_ERROR_CODE" = "1001" ] || [ "$LOGIN_ERROR_CODE" = "1007" ]; then
  mark_warn "Login failed with plain password, retrying with MD5 password"
  LOGIN_PASSWORD="$(md5_text "$PASSWORD")"
  if [ -z "$LOGIN_PASSWORD" ]; then
    mark_fail "Cannot compute MD5 password"
    exit 1
  fi

  login_with_password "$LOGIN_PASSWORD"
  LOGIN_ERROR_CODE="$(response_error_code)"

  if response_success && [ -n "$SESSION_KEY" ]; then
    mark_pass "Login legacy player with MD5 password (c=3)"
  elif [ "$LOGIN_ERROR_CODE" = "2001" ]; then
    mark_warn "Login with MD5 reached nickname setup"
  else
    mark_fail "Login failed with plain and MD5 password, errorCode=${LOGIN_ERROR_CODE:-unknown}"
    exit 1
  fi
else
  mark_fail "Login failed, errorCode=${LOGIN_ERROR_CODE:-unknown}"
  exit 1
fi

if [ -z "$SESSION_KEY" ]; then
  legacy_get "Set nickname (c=5)" \
    "c=5" \
    "un=$USERNAME" \
    "pw=$LOGIN_PASSWORD" \
    "nn=$NICKNAME"
  extract_login_fields

  NICK_ERROR_CODE="$(response_error_code)"
  if response_success && [ -n "$SESSION_KEY" ]; then
    mark_pass "Set nickname (c=5)"
  elif [ "$NICK_ERROR_CODE" = "106" ]; then
    NICKNAME="p${SHORT_SUFFIX}"
    mark_warn "Nickname format rejected, retrying with $NICKNAME"
    legacy_get "Set fallback nickname (c=5)" \
      "c=5" \
      "un=$USERNAME" \
      "pw=$LOGIN_PASSWORD" \
      "nn=$NICKNAME"
    extract_login_fields
    require_success_or_allowed "Set fallback nickname (c=5)"
  elif [ "$NICK_ERROR_CODE" = "1013" ]; then
    mark_warn "Nickname already exists on account, retrying login"
    login_with_password "$LOGIN_PASSWORD"
    extract_login_fields
    require_success_or_allowed "Login after existing nickname (c=3)"
  else
    mark_fail "Set nickname failed, errorCode=${NICK_ERROR_CODE:-unknown}"
    exit 1
  fi
fi

if [ -z "$SESSION_KEY" ]; then
  mark_fail "sessionKey is empty after login/nickname flow"
  exit 1
fi

if [ -z "$ACCESS_TOKEN" ]; then
  mark_warn "accessToken is empty; token based legacy probes will probably return 1001/1014"
else
  legacy_get "Login by access token (c=2)" \
    "c=2" \
    "nn=$NICKNAME" \
    "at=$ACCESS_TOKEN"
  require_success_or_allowed "Login by access token (c=2)"
  extract_login_fields
fi

print_header "3. Config And Static APIs"
probe_json_or_nonempty "Get app config web (c=6)" "c=6" "v=1" "pf=web" "did=$DEVICE_ID" "vnt="
probe_json_or_nonempty "Get app config android (c=6)" "c=6" "v=1" "pf=ad" "did=$DEVICE_ID" "vnt="
probe_json_or_nonempty "Get app config ios (c=6)" "c=6" "v=1" "pf=ios" "did=$DEVICE_ID" "vnt="
probe_json_or_nonempty "Get config admin (c=10)" "c=10"
probe_json_or_nonempty "Get VinPlus config ios (c=11)" "c=11" "pf=ios"
probe_json_or_nonempty "Get VinPlus config android (c=11)" "c=11" "pf=ad"
probe_json_or_nonempty "Get game common (c=129)" "c=129"
probe_json_or_nonempty "Get billing config (c=130)" "c=130"

print_header "4. Player Account Read APIs"
probe_call "Get VP point (c=126)" "c=126" "nn=$NICKNAME"
probe_call "Money history old (c=301)" "c=301" "nn=$NICKNAME" "mt=$MONEY_TYPE" "p=$PAGE"
probe_call "Money history token (c=302)" "c=302" "nn=$NICKNAME" "at=$ACCESS_TOKEN" "mt=$MONEY_TYPE" "p=$PAGE"
probe_call "List agents (c=401)" "c=401"
probe_call "Mailbox old (c=402)" "c=402" "nn=$NICKNAME" "p=$PAGE"
probe_call "Mailbox token (c=405)" "c=405" "nn=$NICKNAME" "at=$ACCESS_TOKEN" "p=$PAGE"
probe_call "Event VP map (c=501)" "c=501" "nn=$NICKNAME"
probe_call "Event VP top intel (c=502)" "c=502" "nn=$NICKNAME" "at=$ACCESS_TOKEN"
probe_call "Event VP top strong (c=503)" "c=503" "nn=$NICKNAME" "at=$ACCESS_TOKEN"

print_header "5. Game Bai And Tournament APIs"
probe_call "Lucky VIP history (c=12)" "c=12" "nn=$NICKNAME" "p=$PAGE"
probe_call "List poker tour (c=13)" "c=13" "tk=-1" "st=0" "type=0" "p=$PAGE" "s=10"
if [ -n "${POKER_TOUR_ID:-}" ]; then
  probe_call "Poker tour detail (c=14)" "c=14" "tid=$POKER_TOUR_ID"
else
  mark_warn "Skip poker tour detail (c=14): set POKER_TOUR_ID to probe it"
fi
probe_call "Poker ticket (c=15)" "c=15" "nn=$NICKNAME"
probe_call "Game bai no-hu log (c=110)" "c=110" "p=$PAGE" "gn=BaCay"
probe_json_or_nonempty "Game bai hu config (c=111)" "c=111"
probe_call "Top cao thu (c=123)" "c=123" "date=$TODAY" "mt=$MONEY_TYPE" "n=10"
probe_call "Top game tour daily (c=601)" "c=601" "gn=BaCay" "type=1" "date=$DAY_NUM" "month=$MONTH_NUM" "year=$YEAR_NUM"
probe_call "Top game tour monthly (c=601)" "c=601" "gn=BaCay" "type=3" "month=$MONTH_NUM" "year=$YEAR_NUM"
probe_call "Log game tour (c=602)" "c=602" "gn=BaCay" "nn=$NICKNAME" "p=$PAGE"

print_header "6. Minigame APIs"
probe_call "Tai Xiu history (c=100)" "c=100" "un=$NICKNAME" "p=$PAGE" "mt=$MONEY_TYPE"
probe_call "Tai Xiu top win (c=101)" "c=101" "mt=$MONEY_TYPE"
if [ -n "${TAIXIU_REFERENCE_ID:-}" ]; then
  probe_call "Tai Xiu session detail (c=102)" "c=102" "rid=$TAIXIU_REFERENCE_ID" "mt=$MONEY_TYPE"
else
  mark_warn "Skip Tai Xiu session detail (c=102): set TAIXIU_REFERENCE_ID to probe it"
fi
probe_call "Top thanh du daily (c=103)" "c=103" "type=1" "date=$TODAY"
probe_call "Top thanh du monthly (c=103)" "c=103" "type=1" "month=$MONTH" "at=$ACCESS_TOKEN"
probe_call "Rut loc tan loc history (c=104)" "c=104" "un=$NICKNAME" "type=1"
probe_call "Mini Poker history (c=105)" "c=105" "un=$NICKNAME" "p=$PAGE" "mt=$MONEY_TYPE"
probe_call "Mini Poker vinh danh (c=106)" "c=106" "mt=$MONEY_TYPE" "p=$PAGE"
probe_call "Cao Thap history (c=107)" "c=107" "nn=$NICKNAME" "p=$PAGE" "mt=$MONEY_TYPE"
probe_call "Cao Thap vinh danh (c=108)" "c=108" "p=$PAGE" "mt=$MONEY_TYPE"
probe_call "Cao Thap top daily (c=109)" "c=109" "type=0" "date=$TODAY" "at=$ACCESS_TOKEN"
probe_call "Cao Thap top monthly (c=109)" "c=109" "type=1" "month=$MONTH" "at=$ACCESS_TOKEN"
probe_call "Bau Cua top (c=120)" "c=120" "mt=$MONEY_TYPE"
probe_call "Bau Cua history (c=121)" "c=121" "un=$NICKNAME" "p=$PAGE" "mt=$MONEY_TYPE"
probe_call "Toi Chon Ca top (c=122)" "c=122" "date=$TODAY"
probe_call "PokeGo history (c=134)" "c=134" "un=$NICKNAME" "p=$PAGE" "mt=$MONEY_TYPE"
probe_call "PokeGo top (c=135)" "c=135" "mt=$MONEY_TYPE" "p=$PAGE"
probe_call "Lucky history (c=201)" "c=201" "nn=$NICKNAME" "p=$PAGE"
probe_call "Bia history (c=2001)" "c=2001" "un=$NICKNAME" "p=$PAGE" "mt=$MONEY_TYPE"
probe_call "Bia top (c=2002)" "c=2002" "mt=$MONEY_TYPE"

print_header "7. Slot APIs"
probe_call "KhoBau top (c=136)" "c=136" "p=$PAGE" "gn=KhoBau"
probe_call "Slot history (c=137)" "c=137" "un=$NICKNAME" "p=$PAGE" "gn=KhoBau"
probe_call "Slot no-hu history (c=138)" "c=138" "gn=KhoBau" "p=$PAGE"

print_header "8. Payment Read APIs"
probe_json_or_nonempty "Payment type in goldpay (c=3014)" "c=3014" "type=in" "partner=goldpay"
probe_json_or_nonempty "Payment type out goldpay (c=3014)" "c=3014" "type=out" "partner=goldpay"
probe_json_or_nonempty "Payment type in oakpay (c=3014)" "c=3014" "type=in" "partner=oakpay"
probe_json_or_nonempty "Payment type out oakpay (c=3014)" "c=3014" "type=out" "partner=oakpay"

if [ "$ENABLE_EXTERNAL_PAYMENT_PROBES" = "1" ]; then
  print_header "9. External Payment Probes"
  probe_call "Common bank list available (c=3337)" "c=3337" "type=in" "partner=goldpay"
  probe_call "MoPay bank code list (c=3020)" "c=3020"
  probe_call "MoPay bank available deposit (c=3021)" "c=3021"
else
  print_header "9. External Payment Probes"
  mark_warn "Skipped external payment probes; set ENABLE_EXTERNAL_PAYMENT_PROBES=1 to enable"
fi

if [ "$ENABLE_MUTATION_PROBES" = "1" ]; then
  print_header "10. Optional Mutation Probes"
  probe_call "Update avatar (c=125)" "c=125" "nn=$NICKNAME" "avatar=1"
else
  print_header "10. Optional Mutation Probes"
  mark_warn "Skipped mutation probes; set ENABLE_MUTATION_PROBES=1 to enable"
fi

print_header "11. Intentionally Skipped Legacy Commands"
mark_skip "OTP/login-security commands c=4,c=8,c=16,c=131,c=132,c=2000,c=2003,c=2004,c=2005,c=2007,c=3334,c=3335 require real OTP/secret/user security state"
mark_skip "Password recovery commands c=127,c=128,c=133 can send OTP/email and mutate recovery state"
mark_skip "Admin/config mutation c=7 and clear cache c=9999 are not player regression tests"
mark_skip "Mailbox mutation c=403,c=404 can delete or mark messages"
mark_skip "Bot commands c=1001,c=1002 are operational/admin-like flows, not normal player flow"
mark_skip "Payment callbacks/mutations c=2008,c=2009,c=3007-c3019,c=3022-c3028,c=3336,c=3338-c3340 need gateway/order state"
mark_skip "Partner XX commands c=3000-c3006 override older payment IDs in api_portal.xml and require operator signature/playTechKey"
mark_skip "Apple/social login c=2006 and social branches of c=3,c=5 need external provider tokens"

print_header "FINAL RESULT"
echo "USERNAME     = $USERNAME"
echo "PASSWORD     = $PASSWORD"
echo "NICKNAME     = $NICKNAME"
echo "SESSION_KEY  = $SESSION_KEY"
echo "ACCESS_TOKEN = $ACCESS_TOKEN"
echo "LOG_FILE     = $LOG_FILE"
echo ""
echo "Counters:"
echo "  PASS = $PASS_COUNT"
echo "  WARN = $WARN_COUNT"
echo "  FAIL = $FAIL_COUNT"
echo ""
echo "Use NICKNAME + SESSION_KEY to login socket game."
echo "Example Bacay WS: ws://127.0.0.1:21044"

if [ "$FAIL_COUNT" -gt 0 ]; then
  exit 1
fi
