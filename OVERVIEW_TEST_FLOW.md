Here is the translated content in **.md format**, without adding or removing any information:

---

# Bacay Frontend Quickstart

## 1. What the frontend needs to prepare

Before opening a socket, your app must have:

```ts
type AuthData = {
  nickname: string
  sessionKey: string
}
```

These two values are obtained from the HTTP/API login step of the app.

If you don’t have `nickname` and `sessionKey` yet, do not proceed with the socket step.

## 2. Choose connection port

If the frontend is web:

* prioritize using WebSocket

Ports in the current repo/docker may vary:

* TCP: `21043`
* WS: `21044`
* WSS: `21046`

With this local repo:

* if testing with `ws://...` then set `BZ_WS_SSL_ENABLED=false`
* if `BZ_WS_SSL_ENABLED=true` then test with `wss://...`
* WebSocket path should not use `/`
* safe path for testing is `/websocket`

Example local:

```text
ws://127.0.0.1:21044/websocket
```

Frontend should have config:

```ts
type BacaySocketConfig = {
  wsUrl: string
  wssUrl?: string
  tcpHost?: string
  tcpPort?: number
}
```

## 2.1 Local test mode of this repo

Current local repo config:

```text
dev_mod=1
enable_payment=0
```

Meaning:

* `dev_mod=1`: server still accepts login payload `nickname + sessionKey`, but validates using internal dev branch instead of real user service
* `enable_payment=0`: joining room uses simulated money, does not call external money service

Verified error code:

```text
3004 -> 03 = MONEY_ERROR
```

If `enable_payment=1` is enabled in Docker local and the test user has no balance in external money service, join room will fail with this error.

## 3. Correct flow must follow this order

```text
HTTP/API login
-> get nickname + sessionKey
-> open socket
-> send core login
-> login success
-> join room
-> receive 3118
-> then start Bacay flow
```

Not allowed:

* send Bacay commands before login success
* send Bacay commands before `3118`

## 4. Step 1: open socket

Frontend needs to:

* connect `ws://...` or `wss://...`
* wait for `open`
* listen to `message`
* listen to `close`
* listen to `error`

At this step:

* only transport connection exists
* not logged in yet
* not in room yet

## 5. Step 2: send login

Bacay login uses:

```ts
type CoreLoginPayload = {
  nickname: string
  sessionKey: string
}
```

Field order:

1. `nickname`
2. `sessionKey`

Meaning:

* `nickname`: username
* `sessionKey`: session token returned from backend

Very important:

* this is BitZero core login
* not Bacay command `3101..3123`
* BitZero packet wrapper reversed from current core:

```text
WebSocket frame client -> server:
00 00 00 | controllerId(1 byte) | actionId(uint16_be) | content

TCP frame client -> server:
80 | payloadLen(uint16_be) | controllerId(1 byte) | actionId(uint16_be) | content
```

For Bacay login:

```text
controllerId = 1
actionId = 1
content = string(nickname) + string(sessionKey)
```

BitZero string encoding:

```text
uint16_be length + utf8 bytes
```

Repo already has script to generate frames:

```bash
node scripts/build-bitzero-frames.js
```

Successful login frame response:

```text
01000100
```

## 6. Step 3: wait for login success

After sending login, frontend only handles 2 cases:

1. `login success`
2. `login fail`

Verified login error codes:

* `1`: invalid session key
* `2`: rejected / blocked
* `3`: server maintenance

FE should have simple state:

```ts
type LoginState =
  | "idle"
  | "socket-open"
  | "login-sent"
  | "login-ok"
  | "login-fail"
```

Only proceed when `login-ok`.

## 7. Step 4: join room

After login success, frontend must join room via core game-room module.

Two main ways:

### Method A: join by `roomId`

Payload:

```ts
type JoinRoomByIdPayload = {
  roomId: number
  password: string
}
```

Use when:

* UI knows specific room
* user selects table

Wrapper route:

```text
controllerId = 1
actionId = 3015
```

### Method B: join by filter

Payload:

```ts
type JoinGameRoomPayload = {
  moneyType: number
  maxUserPerRoom: number
  moneyBet: number
  rule: number
}
```

Use when:

* UI wants auto-join by bet level

Wrapper route:

```text
controllerId = 1
actionId = 3001
```

If fetching room list before joining:

```text
controllerId = 1
actionId = 3014
payload = moneyType + maxUserPerRoom + moneyBet + rule + from + to
```

With current local config, filter join tested successfully:

```text
moneyType = 0
maxUserPerRoom = 8
moneyBet = 1000
rule = 0
```

## 8. Step 5: wait for `3118`

This is the most critical milestone.

When join room succeeds, server sends:

```text
3118 - JOIN_ROOM_SUCCESS
```

Only after `3118`, frontend is considered:

* inside Bacay table
* ready to build game state
* ready to receive next game packets

Before `3118`:

* do not render gameplay actions
* do not send `3102`, `3109`, `3112`, `3106`, `3104`, `3101`

## 9. What frontend must extract from `3118`

Upon receiving `3118`, frontend must at minimum store:

```ts
type JoinRoomSuccessState = {
  uChair: number
  chuongChair: number
  moneyBet: number
  roomId: number
  gameId: number
  moneyType: number
  rule: number
  playerStatus: number[]
  gameAction: number
  countDownTime: number
}
```

Also includes 8-seat info:

* `nickName`
* `avatarUrl`
* `currentMoney`

Principle:

* map state by `chair`
* not by packet arrival order

## 10. After `3118`, enter Bacay flow

Basic flow:

```text
3118 JOIN_ROOM_SUCCESS
-> 3107 AUTO_START or user sends 3102 START
-> 3114 BET_PHASE
-> user places bet
-> 3105 DEAL_CARDS
-> 3101 OPEN_CARDS
-> 3103 END_GAME
-> 3123 UPDATE_MATCH
```

Commands use same WebSocket wrapper:

```text
00 00 00 | 01 | commandId(uint16_be) | payload
```

Example tested:

```text
3111 - leave room
hex = 00 00 00 01 0c 27
server response = 3119 - user leave
```

## 11. Commands frontend sends in game

Main group:

* `3102`: start game
* `3109`: bet
* `3112`: into ga
* `3106`: ke cua
* `3104`: request danh bien
* `3108`: accept danh bien
* `3101`: open cards
* `3111`: register leave
* `3116`: register continue

## 12. Payload frontend must know

```ts
type DatCuocPayload = {
  rate: number
}

type KeCuaPayload = {
  chair: number
  rate: number
}

type DanhBienPayload = {
  chair: number
  rate: number
}

type DongYDanhBienPayload = {
  chair: number
}
```

Commands without custom payload:

* `3102`
* `3112`
* `3101`
* `3111`
* `3116`

## 13. Short checklist for correct frontend implementation

1. HTTP/API login to get `nickname`, `sessionKey`.
2. Open socket.
3. Send core login with `nickname + sessionKey`.
4. Wait for login success.
5. Join room.
6. Wait for `3118`.
7. Build store by `chair`.
8. Only then send Bacay commands.

## 14. Quick test in this repo

Generate frame from `.env`:

```bash
node scripts/build-bitzero-frames.js
```

Run verified flow:

```bash
node scripts/test-bacay-flow.js
```

Expected result:

```text
cmd=1
cmd=3118
cmd=3119
```

Flow:

```text
open WS -> login -> join room -> receive 3118 -> send 3111 -> receive 3119
```

## 15. If frontend is stuck

If stuck before `3118`, the issue is almost always one of:

* incorrect login packet
* incorrect join room packet
* wrong port / wrong transport

If `3118` is received but cannot play, issue is usually:

* incorrect game payload parsing
* wrong state mapping by `chair`
* sending command in wrong phase

```

:contentReference[oaicite:0]{index=0}
```
