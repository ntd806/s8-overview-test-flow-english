#!/bin/bash

INPUT_PORTAL_URL="${PORTAL_URL-}"
INPUT_PORTAL_HOST="${PORTAL_HOST-}"
INPUT_HOST="${HOST-}"
INPUT_IP="${IP-}"
INPUT_PORTAL_PORT="${PORTAL_PORT-}"
INPUT_PORTAL_SCHEME="${PORTAL_SCHEME-}"

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
PORTAL_URL="${INPUT_PORTAL_URL:-${PORTAL_URL:-${PORTAL_SCHEME}://${PORTAL_HOST}:${PORTAL_PORT}/api}}"

RUN_SUFFIX="${RUN_SUFFIX:-$(date +%s)}"
SHORT_SUFFIX="$(printf "%s" "$RUN_SUFFIX" | tail -c 7)"
USERNAME="${USERNAME:-test${SHORT_SUFFIX}}"
PASSWORD="${PASSWORD:-123456}"
NICKNAME="${NICKNAME:-play_${SHORT_SUFFIX}}"

json_get() {
  local json="$1"
  local key="$2"
  echo "$json" | jq -r ".$key // empty"
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

echo "=============================="
echo " STEP 1: Get captcha"
echo "=============================="

CAPTCHA_JSON=$(curl -s "$PORTAL_URL?c=124")

CID=$(json_get "$CAPTCHA_JSON" "id")
IMG=$(json_get "$CAPTCHA_JSON" "img")

if [ -z "$CID" ]; then
  echo "ERROR: cannot get captcha id"
  echo "$CAPTCHA_JSON"
  exit 1
fi

echo "$IMG" | base64 --decode > captcha.png

echo "Captcha ID: $CID"
echo "Saved captcha image: captcha.png"

if command -v open >/dev/null 2>&1; then
  open captcha.png
elif command -v xdg-open >/dev/null 2>&1; then
  xdg-open captcha.png
else
  echo "Please open captcha.png and read the 3-char captcha."
fi

echo ""
read -p "Enter captcha: " CAPTCHA

if [ -z "$CAPTCHA" ]; then
  echo "ERROR: captcha is empty"
  exit 1
fi

echo ""
echo "=============================="
echo " STEP 2: Register user"
echo "=============================="

REGISTER_RESPONSE=$(curl -s "$PORTAL_URL?c=1&un=$USERNAME&pw=$PASSWORD&cp=$CAPTCHA&cid=$CID")
echo "$REGISTER_RESPONSE"

REGISTER_SUCCESS=$(json_get "$REGISTER_RESPONSE" "success")
REGISTER_ERROR_CODE=$(json_get "$REGISTER_RESPONSE" "errorCode")

if [ "$REGISTER_SUCCESS" != "true" ] && [ "$REGISTER_ERROR_CODE" != "1006" ]; then
  echo "ERROR: register failed"
  echo "errorCode = $REGISTER_ERROR_CODE"
  exit 1
fi

if [ "$REGISTER_ERROR_CODE" = "1006" ]; then
  echo "User already exists, continue with login."
else
  echo "Register success."
fi

echo ""
echo "=============================="
echo " STEP 3: Login"
echo "=============================="

LOGIN_PASSWORD="$PASSWORD"
LOGIN_RESPONSE=$(curl -s "$PORTAL_URL?c=3&un=$USERNAME&pw=$LOGIN_PASSWORD")
echo "$LOGIN_RESPONSE"

LOGIN_SUCCESS=$(json_get "$LOGIN_RESPONSE" "success")
LOGIN_ERROR_CODE=$(json_get "$LOGIN_RESPONSE" "errorCode")
SESSION_KEY=$(json_get "$LOGIN_RESPONSE" "sessionKey")

if [ "$LOGIN_SUCCESS" = "true" ] && [ -n "$SESSION_KEY" ]; then
  echo "Login success. sessionKey received from login."
elif [ "$LOGIN_ERROR_CODE" = "2001" ]; then
  echo "User has no nickname yet. Continue to set nickname."
elif [ "$LOGIN_ERROR_CODE" = "1001" ]; then
  echo "Login returned errorCode=1001 with plain password."
  echo "Try login again with MD5 password to detect local password-format mismatch."

  PASSWORD_MD5=$(md5_text "$PASSWORD")

  if [ -n "$PASSWORD_MD5" ]; then
    LOGIN_PASSWORD="$PASSWORD_MD5"
    LOGIN_RESPONSE=$(curl -s "$PORTAL_URL?c=3&un=$USERNAME&pw=$LOGIN_PASSWORD")
    echo "$LOGIN_RESPONSE"

    LOGIN_SUCCESS=$(json_get "$LOGIN_RESPONSE" "success")
    LOGIN_ERROR_CODE=$(json_get "$LOGIN_RESPONSE" "errorCode")
    SESSION_KEY=$(json_get "$LOGIN_RESPONSE" "sessionKey")

    if [ "$LOGIN_SUCCESS" = "true" ] && [ -n "$SESSION_KEY" ]; then
      echo "Login success with MD5 password. Backend local expects stored/hashed password format."
    elif [ "$LOGIN_ERROR_CODE" = "2001" ]; then
      echo "Login with MD5 password reached nickname step. Continue to set nickname."
    else
      echo "ERROR: login failed with both plain password and MD5 password"
      echo "last errorCode = $LOGIN_ERROR_CODE"
      echo "Hint: local backend may still need local_legacy_register_fix.sql re-import + Portal restart."
      exit 1
    fi
  else
    echo "ERROR: cannot compute MD5 password for fallback login"
    exit 1
  fi
else
  echo "ERROR: login failed"
  echo "errorCode = $LOGIN_ERROR_CODE"
  exit 1
fi

echo ""
echo "=============================="
echo " STEP 4: Resolve nickname/sessionKey"
echo "=============================="

if [ -z "$SESSION_KEY" ]; then
  NICK_RESPONSE=$(curl -s "$PORTAL_URL?c=5&un=$USERNAME&pw=$LOGIN_PASSWORD&nn=$NICKNAME")
  echo "$NICK_RESPONSE"

  NICK_SUCCESS=$(json_get "$NICK_RESPONSE" "success")
  NICK_ERROR_CODE=$(json_get "$NICK_RESPONSE" "errorCode")
  SESSION_KEY=$(json_get "$NICK_RESPONSE" "sessionKey")

  if [ "$NICK_SUCCESS" = "true" ] && [ -n "$SESSION_KEY" ]; then
    echo "Set nickname success. sessionKey received."
  elif [ "$NICK_ERROR_CODE" = "106" ]; then
    echo "Nickname format invalid. Retry with shorter nickname."
    NICKNAME="p${SHORT_SUFFIX}"
    NICK_RESPONSE=$(curl -s "$PORTAL_URL?c=5&un=$USERNAME&pw=$LOGIN_PASSWORD&nn=$NICKNAME")
    echo "$NICK_RESPONSE"
    NICK_SUCCESS=$(json_get "$NICK_RESPONSE" "success")
    NICK_ERROR_CODE=$(json_get "$NICK_RESPONSE" "errorCode")
    SESSION_KEY=$(json_get "$NICK_RESPONSE" "sessionKey")
    if [ "$NICK_SUCCESS" = "true" ] && [ -n "$SESSION_KEY" ]; then
      echo "Set nickname success after retry. sessionKey received."
    else
      echo "ERROR: nickname retry failed"
      echo "errorCode = $NICK_ERROR_CODE"
      exit 1
    fi
  elif [ "$NICK_ERROR_CODE" = "1013" ]; then
    echo "Nickname already exists on this account. Login again to get sessionKey."
    LOGIN_RESPONSE=$(curl -s "$PORTAL_URL?c=3&un=$USERNAME&pw=$LOGIN_PASSWORD")
    echo "$LOGIN_RESPONSE"
    SESSION_KEY=$(json_get "$LOGIN_RESPONSE" "sessionKey")
  else
    echo "ERROR: cannot get sessionKey from set nickname"
    echo "errorCode = $NICK_ERROR_CODE"
    exit 1
  fi
fi

if [ -z "$SESSION_KEY" ]; then
  echo "ERROR: sessionKey is still empty after login/set nickname flow"
  exit 1
fi

echo ""
echo "=============================="
echo " STEP 5: Get game config"
echo "=============================="

CONFIG_RESPONSE=$(curl -s "$PORTAL_URL?c=6&v=1&pf=web&did=test&vnt=")
echo "$CONFIG_RESPONSE"

echo ""
echo "=============================="
echo " FINAL RESULT"
echo "=============================="

echo "USERNAME   = $USERNAME"
echo "PASSWORD   = $PASSWORD"
echo "NICKNAME   = $NICKNAME"
echo "SESSIONKEY = $SESSION_KEY"

echo ""
echo "Use nickname + sessionKey to login socket game."
echo "Example Bacay WS:"
echo "ws://127.0.0.1:21044"
