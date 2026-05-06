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
