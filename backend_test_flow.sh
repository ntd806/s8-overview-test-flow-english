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
BACKEND_SCHEME="${BACKEND_SCHEME:-http}"
BACKEND_HOST="${BACKEND_HOST:-${HOST}}"
APP_PORT="${APP_PORT:-${BACKEND_PORT:-8082}}"
BACKEND_PATH="${BACKEND_PATH:-/api_backend}"
BACKEND_BASE_URL="${BACKEND_BASE_URL:-${BACKEND_SCHEME}://${BACKEND_HOST}:${APP_PORT}}"
BACKEND_URL="${BACKEND_URL:-$(trim_trailing_slash "$BACKEND_BASE_URL")$BACKEND_PATH}"
CURL_TIMEOUT="${CURL_TIMEOUT:-30}"

RUN_SUFFIX="${RUN_SUFFIX:-$(date +%s)}"
SHORT_SUFFIX="$(printf "%s" "$RUN_SUFFIX" | tail -c 7)"

ADMIN_USERNAME="${ADMIN_USERNAME:-}"
ADMIN_PASSWORD="${ADMIN_PASSWORD:-}"
ADMIN_OTP="${ADMIN_OTP:-}"

TARGET_NICKNAME="${TARGET_NICKNAME:-test}"
TARGET_USERNAME="${TARGET_USERNAME:-}"
MONEY_TYPE="${MONEY_TYPE:-vin}"
MONEY_AMOUNT="${MONEY_AMOUNT:-1}"
PAGE="${PAGE:-1}"
TOTAL_RECORD="${TOTAL_RECORD:-50}"

TODAY_SQL="${TODAY_SQL:-$(date +%F)}"
START_SQL="${START_SQL:-${TODAY_SQL} 00:00:00}"
END_SQL="${END_SQL:-${TODAY_SQL} 23:59:59}"
REPORT_DATE="${REPORT_DATE:-$(date +%d-%m-%Y)}"

OPERATOR_CODE="${OPERATOR_CODE:-${OP:-OP001}}"
TEST_OPERATOR_CODE="${TEST_OPERATOR_CODE:-OPTEST${SHORT_SUFFIX}}"
TEST_OPERATOR_NAME="${TEST_OPERATOR_NAME:-Test Operator ${SHORT_SUFFIX}}"
TEST_OPERATOR_DB="${TEST_OPERATOR_DB:-vinplay_optest_${SHORT_SUFFIX}}"
TEST_OPERATOR_MONGO_DB="${TEST_OPERATOR_MONGO_DB:-${TEST_OPERATOR_DB}_logs}"

MYSQL_HOST="${MYSQL_HOST:-mysql}"
MYSQL_PORT="${MYSQL_PORT:-3306}"
MYSQL_USERNAME="${MYSQL_USERNAME:-${MYSQL_USER:-appuser}}"
MYSQL_PASSWORD="${MYSQL_PASSWORD:-appPass_123}"
MONGO_HOST="${MONGO_HOST:-mongodb}"
MONGO_PORT="${MONGO_PORT:-27017}"
MONGO_AUTH_DATABASE="${MONGO_AUTH_DATABASE:-admin}"
MONGO_USERNAME="${MONGO_USERNAME:-${MONGO_ROOT_USERNAME:-root}}"
MONGO_PASSWORD="${MONGO_PASSWORD:-${MONGO_ROOT_PASSWORD:-rootStrongPass_123}}"

BACKEND_BASIC_AUTH="${BACKEND_BASIC_AUTH:-}"
BACKEND_BASIC_USER="${BACKEND_BASIC_USER:-}"
BACKEND_BASIC_PASSWORD="${BACKEND_BASIC_PASSWORD:-}"

ENABLE_BACKEND_MUTATIONS="${ENABLE_BACKEND_MUTATIONS:-0}"
RUN_RESET_PASSWORD="${RUN_RESET_PASSWORD:-$ENABLE_BACKEND_MUTATIONS}"
RUN_UPDATE_MONEY="${RUN_UPDATE_MONEY:-$ENABLE_BACKEND_MUTATIONS}"
RUN_SEND_SMS="${RUN_SEND_SMS:-$ENABLE_BACKEND_MUTATIONS}"
RUN_SEND_MAIL="${RUN_SEND_MAIL:-$ENABLE_BACKEND_MUTATIONS}"
RUN_OPERATOR_MUTATIONS="${RUN_OPERATOR_MUTATIONS:-$ENABLE_BACKEND_MUTATIONS}"

BACKEND_OTP="${BACKEND_OTP:-000000}"
BACKEND_OTP_TYPE="${BACKEND_OTP_TYPE:-0}"
SMS_MOBILE="${SMS_MOBILE:-}"
SMS_CONTENT="${SMS_CONTENT:-backend_test_flow ${SHORT_SUFFIX}}"
MAIL_TITLE="${MAIL_TITLE:-backend_test_flow ${SHORT_SUFFIX}}"
MAIL_CONTENT="${MAIL_CONTENT:-Smoke mail from backend_test_flow ${SHORT_SUFFIX}}"

LOG_DIR="${LOG_DIR:-logs}"
LOG_FILE="${LOG_FILE:-${LOG_DIR}/backend_test_flow_${SHORT_SUFFIX}.log}"
LOG_TO_STDOUT="${LOG_TO_STDOUT:-0}"

PASS_COUNT=0
WARN_COUNT=0
FAIL_COUNT=0
LAST_RESPONSE=""
SESSION_KEY=""
ACCESS_TOKEN=""
API_CALL_COUNT=0
LAST_HTTP_CODE=""
LAST_CURL_RC=0
LAST_CURL_TIME=""
LAST_CURL_EFFECTIVE_URL=""
LAST_CURL_STDERR=""
CREATED_OPERATOR_ID="${CREATED_OPERATOR_ID:-}"
CREATED_OPERATOR_API_KEY=""
CREATED_OPERATOR_SECRET_KEY=""
CREATED_OPERATOR_CONFIG_ID=""

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
    pw|otp|apiKey|secretKey|mysqlPassword|mongoPassword|at|Authorization)
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

append_auth_args() {
  if [ -n "$BACKEND_BASIC_AUTH" ]; then
    CURL_ARGS+=(-H "Authorization: $BACKEND_BASIC_AUTH")
  elif [ -n "$BACKEND_BASIC_USER" ] || [ -n "$BACKEND_BASIC_PASSWORD" ]; then
    CURL_ARGS+=(-u "${BACKEND_BASIC_USER}:${BACKEND_BASIC_PASSWORD}")
  fi
}

backend_get() {
  local step="$1"
  shift

  CURL_ARGS=(-sS --max-time "$CURL_TIMEOUT" --get "$BACKEND_URL")
  append_auth_args

  local param
  for param in "$@"; do
    CURL_ARGS+=(--data-urlencode "$param")
  done

  run_curl_request "$step" "GET" "$BACKEND_URL" "$@"
}

response_success() {
  local trimmed
  trimmed="$(printf "%s" "$LAST_RESPONSE" | tr -d '\r\n[:space:]')"
  if [ "$trimmed" = "0" ]; then
    return 0
  fi

  if ! is_json "$LAST_RESPONSE"; then
    return 1
  fi

  local success
  local error_code
  success="$(json_get "$LAST_RESPONSE" ".success")"
  error_code="$(json_get "$LAST_RESPONSE" ".errorCode")"

  [ "$success" = "true" ] || [ "$error_code" = "0" ]
}

response_error_code() {
  if is_json "$LAST_RESPONSE"; then
    json_get "$LAST_RESPONSE" ".errorCode"
  else
    printf "%s" "$LAST_RESPONSE" | tr -d '\r\n'
  fi
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

probe_call() {
  local step="$1"
  shift

  if ! backend_get "$step" "$@"; then
    mark_warn "$step curl failed"
    return 0
  fi

  if response_success; then
    mark_pass "$step"
    return 0
  fi

  if [ -n "$LAST_RESPONSE" ]; then
    mark_warn "$step returned ${LAST_RESPONSE:0:180}"
    return 0
  fi

  mark_warn "$step returned empty response"
}

mutation_call() {
  local step="$1"
  shift

  if ! backend_get "$step" "$@"; then
    mark_warn "$step curl failed"
    return 0
  fi

  if response_success; then
    mark_pass "$step"
    return 0
  fi

  local error_code
  error_code="$(response_error_code)"
  mark_warn "$step did not complete successfully, result=${error_code:-unknown}"
}

raw_backend_health() {
  CURL_ARGS=(-sS --max-time "$CURL_TIMEOUT" "$BACKEND_URL")
  run_curl_request "Backend route smoke" "GET" "$BACKEND_URL"
}

print_header "VINPLAYBACKEND API FULL FLOW"
echo "Started at     : $(date '+%Y-%m-%d %H:%M:%S %Z')"
echo "Env file       : ${LOADED_ENV_FILE:-not loaded}"
echo "Backend URL    : $BACKEND_URL"
echo "Target nickname: $TARGET_NICKNAME"
echo "Operator code  : $OPERATOR_CODE"
echo "Log file       : $LOG_FILE"
echo ""
echo "Mutation flags:"
echo "  ENABLE_BACKEND_MUTATIONS=$ENABLE_BACKEND_MUTATIONS"
echo "  RUN_RESET_PASSWORD=$RUN_RESET_PASSWORD"
echo "  RUN_UPDATE_MONEY=$RUN_UPDATE_MONEY"
echo "  RUN_SEND_SMS=$RUN_SEND_SMS"
echo "  RUN_SEND_MAIL=$RUN_SEND_MAIL"
echo "  RUN_OPERATOR_MUTATIONS=$RUN_OPERATOR_MUTATIONS"

print_header "0. Preflight"
require_tool curl
require_tool jq
mark_pass "Required tools found"

if ! raw_backend_health; then
  mark_fail "Backend route is not reachable"
  exit 1
fi
require_nonempty_response "Backend route responded"

print_header "1. Admin Login And Basic User Checks"
if [ -n "$ADMIN_USERNAME" ] && [ -n "$ADMIN_PASSWORD" ]; then
  probe_call "Login admin (c=701)" "c=701" "un=$ADMIN_USERNAME" "pw=$ADMIN_PASSWORD" "otp=$ADMIN_OTP"
  if is_json "$LAST_RESPONSE"; then
    SESSION_KEY="$(json_get "$LAST_RESPONSE" ".sessionKey")"
    ACCESS_TOKEN="$(json_get "$LAST_RESPONSE" ".accessToken")"
  fi
else
  mark_skip "Login admin (c=701): set ADMIN_USERNAME and ADMIN_PASSWORD to run"
fi

probe_call "Check nickname (c=716)" "c=716" "nn=$TARGET_NICKNAME"

if [ -n "$BACKEND_BASIC_AUTH" ] || [ -n "$BACKEND_BASIC_USER" ] || [ -n "$BACKEND_BASIC_PASSWORD" ]; then
  probe_call "Get user by nickname with Basic auth (c=102)" "c=102" "nn=$TARGET_NICKNAME"
else
  mark_skip "Get user by nickname (c=102): set BACKEND_BASIC_AUTH or BACKEND_BASIC_USER/BACKEND_BASIC_PASSWORD"
fi

probe_call "Search user admin (c=104)" \
  "c=104" "un=$TARGET_USERNAME" "nn=$TARGET_NICKNAME" "m=" "fd=nick_name" "srt=desc" \
  "ts=$START_SQL" "te=$END_SQL" "dl=" "bt=" "lk=1" "email=" "p=$PAGE" "tr=$TOTAL_RECORD"
probe_call "List user info (c=109)" "c=109" "nn=$TARGET_NICKNAME" "ip=" "ts=$START_SQL" "te=$END_SQL" "type=" "p=$PAGE"
probe_call "Get nicknames list (c=126)" "c=126" "nn=$TARGET_NICKNAME"
probe_call "Get user index (c=142)" "c=142" "ts=$START_SQL" "te=$END_SQL"
probe_call "Get total vin by user (c=407)" "c=407" "nn=$TARGET_NICKNAME"

print_header "2. Monitoring, Cache, And Config"
probe_call "Get CCU (c=108)" "c=108" "ts=$START_SQL" "te=$END_SQL"
probe_call "Check cache users entry (c=1992)" "c=1992" "cn=users" "k=$TARGET_NICKNAME"
probe_call "Get game config web (c=601)" "c=601" "pf=web" "nm="
probe_call "Get game config android (c=601)" "c=601" "pf=ad" "nm="
probe_call "Get game config ios (c=601)" "c=601" "pf=ios" "nm="

print_header "3. Reports And Logs"
probe_call "Report money system (c=7)" "c=7" "ts=$REPORT_DATE" "te=$REPORT_DATE"
probe_call "Report money user (c=8)" "c=8" "nn=$TARGET_NICKNAME" "ts=$REPORT_DATE" "te=$REPORT_DATE"
probe_call "Report total money (c=9)" "c=9" "ts=$REPORT_DATE" "te=$REPORT_DATE" "p=$PAGE"
probe_call "Report top game all (c=12)" "c=12" "ac=all" "n=10" "ts=$REPORT_DATE" "te=$REPORT_DATE"
probe_call "Search log game by nickname (c=2)" "c=2" "sid=" "nn=$TARGET_NICKNAME" "gn=" "ts=$START_SQL" "te=$END_SQL" "mt=$MONEY_TYPE" "p=$PAGE"
probe_call "Search log money user (c=3)" "c=3" "nn=$TARGET_NICKNAME" "un=$TARGET_USERNAME" "ts=$START_SQL" "te=$END_SQL" "mt=$MONEY_TYPE" "ag=" "sn=" "p=$PAGE" "lk=1" "tr=$TOTAL_RECORD"
probe_call "Search TaiXiu result (c=137)" "c=137" "rid=" "ts=$START_SQL" "te=$END_SQL" "mt=$MONEY_TYPE" "p=$PAGE"

print_header "4. Minigame And Game Logs"
probe_call "BauCua result log (c=119)" "c=119" "rid=" "r=" "ts=$START_SQL" "te=$END_SQL" "p=$PAGE"
probe_call "BauCua transaction log (c=501)" "c=501" "rid=" "nn=$TARGET_NICKNAME" "r=" "ts=$START_SQL" "te=$END_SQL" "mt=$MONEY_TYPE" "p=$PAGE"
probe_call "CaoThap log (c=503)" "c=503" "nn=$TARGET_NICKNAME" "tid=" "r=" "ts=$START_SQL" "te=$END_SQL" "mt=$MONEY_TYPE" "p=$PAGE"
probe_call "MiniPoker log (c=504)" "c=504" "nn=$TARGET_NICKNAME" "r=" "ts=$START_SQL" "te=$END_SQL" "mt=$MONEY_TYPE" "p=$PAGE"
probe_call "TaiXiu transaction log (c=505)" "c=505" "rid=" "nn=$TARGET_NICKNAME" "bs=" "ts=$START_SQL" "te=$END_SQL" "mt=$MONEY_TYPE" "p=$PAGE"
probe_call "Slot log KhoBau (c=122)" "c=122" "rid=" "un=$TARGET_NICKNAME" "ts=$START_SQL" "te=$END_SQL" "bv=" "gn=KhoBau" "p=$PAGE"

print_header "5. Cashout And Recharge Read APIs"
probe_call "Cashout by bank search (c=112)" "c=112"
probe_call "Cashout by card search (c=113)" "c=113" "nn=$TARGET_NICKNAME" "pv=" "co=" "ts=$START_SQL" "te=$END_SQL" "p=$PAGE" "tid="
probe_call "Recharge all search (c=115)" "c=115"
probe_call "Cashout by momo search (c=182)" "c=182" "nn=$TARGET_NICKNAME" "acc=" "st=" "co=" "ts=$START_SQL" "te=$END_SQL" "p=$PAGE" "tid="

print_header "6. Partner And Operator Read APIs"
probe_call "Partner summary (c=2000)" "c=2000" "op=$OPERATOR_CODE" "ts=$TODAY_SQL" "te=$TODAY_SQL"
probe_call "Partner users (c=2001)" "c=2001" "op=$OPERATOR_CODE" "un=$TARGET_USERNAME" "ts=$TODAY_SQL" "te=$TODAY_SQL" "p=$PAGE"
probe_call "Partner user summary (c=2002)" "c=2002" "op=$OPERATOR_CODE" "nn=$TARGET_NICKNAME" "ts=$TODAY_SQL" "te=$TODAY_SQL"
probe_call "Partner gameplay history (c=2003)" "c=2003" "op=$OPERATOR_CODE" "nn=$TARGET_NICKNAME" "ts=$TODAY_SQL" "te=$TODAY_SQL" "p=$PAGE"
probe_call "Partner transfer history (c=2004)" "c=2004" "op=$OPERATOR_CODE" "nn=$TARGET_NICKNAME" "type=" "status=" "ts=$TODAY_SQL" "te=$TODAY_SQL" "p=$PAGE"
probe_call "Get operator (c=2005)" "c=2005" "op=$OPERATOR_CODE"
probe_call "List operators (c=2006)" "c=2006"

print_header "7. Reset Password, Money, SMS, And Mail Mutations"
if [ "$RUN_RESET_PASSWORD" = "1" ]; then
  mutation_call "Reset password (c=14)" "c=14" "nn=$TARGET_NICKNAME" "otp=$BACKEND_OTP" "type=$BACKEND_OTP_TYPE"
else
  mark_skip "Reset password (c=14): set RUN_RESET_PASSWORD=1 or ENABLE_BACKEND_MUTATIONS=1"
fi

if [ "$RUN_UPDATE_MONEY" = "1" ]; then
  mutation_call "Update money user (c=100)" \
    "c=100" "ac=backend_test_flow" "nn=$TARGET_NICKNAME" "mn=$MONEY_AMOUNT" "mt=$MONEY_TYPE" \
    "rs=backend_test_flow_${SHORT_SUFFIX}" "otp=$BACKEND_OTP" "type=$BACKEND_OTP_TYPE" "nns=$ADMIN_USERNAME"
else
  mark_skip "Update money user (c=100): set RUN_UPDATE_MONEY=1 or ENABLE_BACKEND_MUTATIONS=1"
fi

if [ "$RUN_SEND_SMS" = "1" ]; then
  if [ -n "$SMS_MOBILE" ]; then
    mutation_call "Send SMS (c=718)" "c=718" "m=$SMS_MOBILE" "ct=$SMS_CONTENT"
  else
    mark_warn "Send SMS (c=718) skipped because SMS_MOBILE is empty"
  fi
else
  mark_skip "Send SMS (c=718): set RUN_SEND_SMS=1 or ENABLE_BACKEND_MUTATIONS=1"
fi

if [ "$RUN_SEND_MAIL" = "1" ]; then
  mutation_call "Send mailbox message (c=401)" "c=401" "nn=$TARGET_NICKNAME" "tm=$MAIL_TITLE" "cm=$MAIL_CONTENT"
else
  mark_skip "Send mailbox message (c=401): set RUN_SEND_MAIL=1 or ENABLE_BACKEND_MUTATIONS=1"
fi

print_header "8. Operator Create And Update Mutations"
if [ "$RUN_OPERATOR_MUTATIONS" = "1" ]; then
  mutation_call "Create partner/operator (c=2010)" \
    "c=2010" \
    "operatorCode=$TEST_OPERATOR_CODE" \
    "operatorName=$TEST_OPERATOR_NAME" \
    "tier=SMALL" \
    "mysqlHost=$MYSQL_HOST" \
    "mysqlPort=$MYSQL_PORT" \
    "mysqlDatabase=$TEST_OPERATOR_DB" \
    "mysqlUsername=$MYSQL_USERNAME" \
    "mysqlPassword=$MYSQL_PASSWORD" \
    "mongoHost=$MONGO_HOST" \
    "mongoPort=$MONGO_PORT" \
    "mongoDatabase=$TEST_OPERATOR_MONGO_DB" \
    "mongoAuthDatabase=$MONGO_AUTH_DATABASE" \
    "mongoUsername=$MONGO_USERNAME" \
    "mongoPassword=$MONGO_PASSWORD"

  if is_json "$LAST_RESPONSE"; then
    CREATED_OPERATOR_ID="$(json_get "$LAST_RESPONSE" ".operatorId")"
    CREATED_OPERATOR_API_KEY="$(json_get "$LAST_RESPONSE" ".apiKey")"
    CREATED_OPERATOR_SECRET_KEY="$(json_get "$LAST_RESPONSE" ".secretKey")"
  fi

  if [ -n "$CREATED_OPERATOR_ID" ]; then
    probe_call "Get created operator (c=2005)" "c=2005" "op=$TEST_OPERATOR_CODE"

    mutation_call "Update operator (c=2007)" \
      "c=2007" \
      "id=$CREATED_OPERATOR_ID" \
      "operatorCode=$TEST_OPERATOR_CODE" \
      "operatorName=${TEST_OPERATOR_NAME} Updated" \
      "apiKey=$CREATED_OPERATOR_API_KEY" \
      "secretKey=$CREATED_OPERATOR_SECRET_KEY" \
      "status=ACTIVE" \
      "whitelistedIps=" \
      "allowedScopes=game:read,game:write,balance:read,transfer:write" \
      "rateLimitPerMinute=100" \
      "contactEmail=test-${SHORT_SUFFIX}@example.com" \
      "contactPhone=0900000000" \
      "description=updated_by_backend_test_flow"

    probe_call "Get operator database config (c=2008)" "c=2008" "operator_id=$CREATED_OPERATOR_ID"
    if is_json "$LAST_RESPONSE"; then
      CREATED_OPERATOR_CONFIG_ID="$(json_get "$LAST_RESPONSE" ".operatorDatabaseConfig.id")"
    fi

    if [ -n "$CREATED_OPERATOR_CONFIG_ID" ]; then
      mutation_call "Update operator database config (c=2009)" \
        "c=2009" \
        "id=$CREATED_OPERATOR_CONFIG_ID" \
        "operatorId=$CREATED_OPERATOR_ID" \
        "mysqlHost=$MYSQL_HOST" \
        "mysqlPort=$MYSQL_PORT" \
        "mysqlDatabase=$TEST_OPERATOR_DB" \
        "mysqlUsername=$MYSQL_USERNAME" \
        "mysqlPassword=$MYSQL_PASSWORD" \
        "mysqlMinPool=2" \
        "mysqlMaxPool=5" \
        "mongoHost=$MONGO_HOST" \
        "mongoPort=$MONGO_PORT" \
        "mongoDatabase=$TEST_OPERATOR_MONGO_DB" \
        "mongoAuthDatabase=$MONGO_AUTH_DATABASE" \
        "mongoUsername=$MONGO_USERNAME" \
        "mongoPassword=$MONGO_PASSWORD" \
        "tier=SMALL" \
        "shardGroup=SMALL_A" \
        "useSharedPool=true" \
        "estimatedUserCount=100" \
        "estimatedTps=10" \
        "active=true"
    else
      mark_warn "Update operator database config skipped: cannot extract operatorDatabaseConfig.id from c=2008"
    fi
  else
    mark_warn "Operator update flow skipped: cannot extract operatorId from c=2010"
  fi
else
  mark_skip "Operator create/update (c=2010,c=2007,c=2009): set RUN_OPERATOR_MUTATIONS=1 or ENABLE_BACKEND_MUTATIONS=1"
fi

print_header "9. Intentionally Skipped High-Risk Backend Commands"
mark_skip "Cache write/remove c=702-c715 can change online money/cache/security state"
mark_skip "Agent money transfer/refund c=706,c=711,c=713,c=714,c=724 can move or unfreeze money"
mark_skip "Giftcode create/update/export c=116,c=117,c=128-c136,c=301-c311 can create or expose codes"
mark_skip "Payment callback/recharge/cashout mutations c=124,c=141,c=500,c=514,c=515 depend on real provider/order state"
mark_skip "Bot/admin-chat/marketing c=6,c=1993,c=1994,c=1995,c=723 are operational side effects"
mark_skip "Security disable/update c=22,c=717 requires real OTP/security context"

print_header "FINAL RESULT"
echo "TARGET_NICKNAME            = $TARGET_NICKNAME"
echo "ADMIN_USERNAME             = $ADMIN_USERNAME"
echo "SESSION_KEY                = $SESSION_KEY"
echo "ACCESS_TOKEN               = $ACCESS_TOKEN"
echo "TEST_OPERATOR_CODE         = $TEST_OPERATOR_CODE"
echo "CREATED_OPERATOR_ID        = $CREATED_OPERATOR_ID"
echo "CREATED_OPERATOR_CONFIG_ID = $CREATED_OPERATOR_CONFIG_ID"
echo "LOG_FILE                   = $LOG_FILE"
echo ""
echo "Counters:"
echo "  PASS = $PASS_COUNT"
echo "  WARN = $WARN_COUNT"
echo "  FAIL = $FAIL_COUNT"

if [ "$FAIL_COUNT" -gt 0 ]; then
  exit 1
fi
