# Bacay TypeScript Client Template

This package is a developer-ready TypeScript template for integrating Bacay through WebSocket.

It includes:

- TypeScript typings
- Retry and reconnect logic
- Standard error handling
- Event-based callbacks
- Clean example usage

---

## Integration Flow

```text
HTTP Login
   ↓
Get nickname + sessionKey
   ↓
Connect WebSocket
   ↓
Send Core Login
   ↓
Wait for login success
   ↓
Join room
   ↓
Wait for 3118 JOIN_ROOM_SUCCESS
   ↓
Start Bacay game flow
```

---

## Install

```bash
npm install
```

---

## Build

```bash
npm run build
```

## Docker Check

Run the connectivity and join-room check with your existing environment variables:

```bash
docker build -t bacay-client-check .
docker run --rm --env-file .env bacay-client-check
```

Or run with Docker Compose:

```bash
docker compose up --build
```

The console log now prints each milestone in order:

- load env
- create client
- connect socket
- login success
- join room success

Optional env vars:

- `BACAY_TIMEOUT_MS` to fail if join does not complete in time
- `BACAY_MONEY_TYPE`
- `BACAY_MAX_USER_PER_ROOM`
- `BACAY_MONEY_BET`
- `BACAY_RULE`

## Live Demo With Log File

Run a persistent demo client that:

- connects to Bacay WebSocket
- auto joins room
- auto reacts to common game flow packets
- writes every event to a `.log` file in JSONL format
- includes timestamp, nickname, trace id, room config, packet info, and optional user metadata for DB verification

Go to the Bacay game folder first:

```bash
cd /Users/anthonynguyen/Downloads/s8-overview-test-flow-english/Games/Bacay/bacay-typescript-client-template
```

Install dependencies if needed:

```bash
npm install
```

Run directly with environment variables:

```bash
BACAY_WS_URL=ws://127.0.0.1:21044/websocket \
BACAY_NICKNAME=demo_user \
BACAY_SESSION_KEY=real_session_key \
BACAY_USER_ID=1001 \
BACAY_DB_PLAYER_ID=db-1001 \
BACAY_DEVICE_ID=device-01 \
BACAY_IP_ADDRESS=10.0.0.8 \
npm run demo:live
```

Or create a local `.env` file and export it before running:

```bash
export $(grep -v '^#' .env | xargs)
npm run demo:live
```

Default log output:

```text
logs/bacay-demo-<trace-id>.log
```

The log file contains records such as:

- process start and stop time
- socket open, close, reconnect
- login success or failure
- join room success or failure
- game packets and command ids
- auto actions sent by the client
- user metadata used to compare against database records

Important env vars for live demo:

- `BACAY_WS_URL`
- `BACAY_NICKNAME`
- `BACAY_SESSION_KEY`
- `BACAY_USER_ID`
- `BACAY_USERNAME`
- `BACAY_DISPLAY_NAME`
- `BACAY_DB_PLAYER_ID`
- `BACAY_DEVICE_ID`
- `BACAY_IP_ADDRESS`
- `BACAY_PLATFORM`
- `BACAY_LOG_DIR`
- `BACAY_LOG_FILE`
- `BACAY_TRACE_ID`
- `BACAY_HEARTBEAT_MS`
- `BACAY_AUTO_BET`
- `BACAY_AUTO_VAO_GA`
- `BACAY_AUTO_MO_BAI_DELAY_MS`
- `BACAY_AUTO_DANH_BIEN_CHAIR`
- `BACAY_AUTO_DANH_BIEN_RATE`
- `BACAY_AUTO_KE_CUA_CHAIR`
- `BACAY_AUTO_KE_CUA_RATE`

Example log line:

```json
{"ts":"2026-05-07T07:56:18.645Z","event":"process_start","nickname":"demo_user","traceId":"bacay-demo-...","user":{"userId":"1001","dbPlayerId":"db-1001"}}
```

---

## Basic Usage

```ts
import { BacayFrontendClient } from "./src";

const client = new BacayFrontendClient({
  wsUrl: "ws://127.0.0.1:21044/websocket",
  nickname: "your_nickname",
  sessionKey: "your_session_key",

  reconnect: {
    enabled: true,
    maxAttempts: 5,
    baseDelayMs: 1000,
    maxDelayMs: 10000,
  },

  handlers: {
    onOpen() {
      console.log("Socket opened");
    },

    onLoginSuccess() {
      console.log("Login success");
    },

    onJoinSuccess() {
      console.log("Joined room");
    },

    onGameMessage(packet) {
      console.log("Game packet:", packet);
    },

    onError(error) {
      console.error(error.code, error.message);
    },
  },
});

client.connect();
```

---

## Important Notes

1. You must get `nickname` and `sessionKey` from the HTTP/API login flow before connecting to WebSocket.
2. Do not send game commands before receiving `3118 JOIN_ROOM_SUCCESS`.
3. Reconnect only restores the socket/login/join flow. Your app should still resync UI state when receiving `3110 THONG_TIN_BAN_CHOI`.
4. This is a template, not a production SDK. Please validate packet encoding/decoding with your actual game server protocol.

---

## Error Codes

| Code | Meaning |
|---|---|
| `MISSING_CONFIG` | Required config is missing |
| `SOCKET_NOT_OPEN` | Tried to send while socket is not open |
| `NOT_JOINED_ROOM` | Tried to send game command before joining |
| `LOGIN_FAILED` | Socket login failed |
| `JOIN_FAILED` | Socket join room failed |
| `MAX_RECONNECT_ATTEMPTS` | Reconnect attempts exceeded |
| `PACKET_DECODE_ERROR` | Incoming packet could not be decoded |
| `UNKNOWN_ERROR` | Unknown client error |
