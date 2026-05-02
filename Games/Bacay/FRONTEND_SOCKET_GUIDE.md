````md
# Bacay Frontend Game Integration

This document is written for frontend developers integrating the Bacay game according to the actual flow currently running in the source.

Objectives of this document:

- understand what the frontend needs to prepare before opening a socket
- understand the correct sequence `login -> join room -> receive 3118 -> play game`
- understand the input variables of each step
- understand which packets are milestones for building game state

This document does not follow a packet test/debug perspective. Variables like `BACAY_LOGIN_PACKET_HEX` and `BACAY_JOIN_PACKET_HEX` are not the focus here.

## 1. What the frontend needs to prepare

Before touching the socket, the frontend must have results from the HTTP/API login step of the system:

```ts
type AuthData = {
  nickname: string
  sessionKey: string
}
````

Meaning:

* `nickname`: the username entering the game
* `sessionKey`: session token returned by backend/app

If `nickname` and `sessionKey` are not available, do not proceed with the socket step.

## 2. Correct integration flow

Frontend must follow this exact order:

```text
HTTP/API login
-> get nickname + sessionKey
-> connect socket
-> send core login
-> login success
-> join room
-> receive 3118 JOIN_ROOM_SUCCESS
-> then start Bacay game flow
```

Not allowed:

* sending Bacay commands before login success
* sending Bacay commands before `3118`

## 3. Connection endpoint

According to the current Docker/source repo:

* TCP: `21043`
* WebSocket: `21044`
* WebSocket SSL: `21046`

According to internal app config:

* Internal TCP: `443`
* Internal WebSocket: `444`
* Internal WebSocket SSL: `446`

References:

Frontend web should use:

```text
ws://host:port/websocket
```

or production:

```text
wss://domain/websocket
```

## 4. Step 1: connect socket

Input:

```ts
type SocketConnectInput = {
  wsUrl: string
}
```

Example:

```ts
const socketConfig = {
  wsUrl: "ws://127.0.0.1:21044/websocket",
}
```

Frontend needs to:

* open WebSocket
* wait for `open`
* listen to `message`
* listen to `close`
* listen to `error`

At this step:

* only transport connection exists
* not logged in yet
* not in room yet

## 5. Step 2: send core login

### 5.1 Input data

Frontend sends login with exactly 2 fields:

```ts
type CoreLoginInput = {
  nickname: string
  sessionKey: string
}
```

Field order in body:

1. `nickname`
2. `sessionKey`

This is verified from login source:
* `nickname` first, then `sessionKey`

### 5.2 Login route

This login belongs to BitZero core, not Bacay commands `3101..3123`.

Verified login route:

```text
controllerId = 1
actionId = 1
```

WebSocket frame client -> server:

```text
00 00 00 | controllerId(1 byte) | actionId(uint16_be) | content
```

For login:

```text
content = string(nickname) + string(sessionKey)
```

String format in this flow:

```text
uint16_be length + utf8 bytes
```

### 5.3 Does dev_mod change frontend flow

No.

`dev_mod` does not change what frontend sends. It only changes how server validates after parsing `nickname + sessionKey`.

* `dev_mod=1`: server uses internal dev branch
* `dev_mod=0`: server calls real user service to check session

Frontend still sends the same login input:

```ts
{
  nickname,
  sessionKey,
}
```

## 6. Step 3: wait for login success

After sending login, frontend waits for login response.

Verified login error codes:

* `1`: invalid session key
* `2`: blocked or login rejected
* `3`: server maintenance

Frontend should have at least this state:

```ts
type LoginState =
  | "idle"
  | "socket-open"
  | "login-sent"
  | "login-ok"
  | "login-fail"
```

Only proceed to join room when `login-ok`.

## 7. Step 4: join room

After login success, frontend must join room via core game-room.

There are 2 main ways.

### 7.1 Join by bet filter

Input:

```ts
type JoinByBetInput = {
  moneyType: number
  maxUserPerRoom: number
  moneyBet: number
  rule: number
}
```

Route:

```text
controllerId = 1
actionId = 3001
```

Use when:

* UI wants to auto-join by bet level
* frontend does not need to specify exact room id

Tested local values:

```ts
{
  moneyType: 0,
  maxUserPerRoom: 8,
  moneyBet: 1000,
  rule: 0,
}
```

### 7.2 Join by room id

Input:

```ts
type JoinByRoomIdInput = {
  roomId: number
  password: string
}
```

Route:

```text
controllerId = 1
actionId = 3015
```

Use when:

* frontend already has room list
* user selects a specific table

### 7.3 Get room list if needed

If frontend needs to fetch room list first:

```ts
type RoomListInput = {
  moneyType: number
  maxUserPerRoom: number
  moneyBet: number
  rule: number
  from: number
  to: number
}
```

Route:

```text
controllerId = 1
actionId = 3014
```

## 8. Step 5: wait for `3118`

This is the most important milestone for frontend to start Bacay game.

Successful join room will receive:

```text
3118 - JOIN_ROOM_SUCCESS
```

From this point, frontend can:

* build table state
* render players
* render game phase
* send Bacay commands `3101..3123`

`3118` is the first bootstrap packet of the Bacay game layer.

## 9. Important packets frontend must handle

Core packets:

* `3118`: initial state after join room
* `3110`: strongest full sync when reconnect
* `3103`: final result of round
* `3123`: reset for next round

Phase/gameplay packets:

* `3107`: auto start
* `3114`: invite to bet
* `3105`: deal cards
* `3101`: open cards

Room events:

* `3121`: new user joins
* `3119`: user leaves room
* `3117`: change room owner
* `3113`: change banker
* `3120`: kick

## 10. Bacay commands after joining room

Only send after `3118`.

Important client -> server commands:

* `3102`: start round
* `3109`: bet
* `3112`: into ga
* `3106`: ke cua
* `3104`: danh bien
* `3108`: accept danh bien
* `3101`: open cards
* `3111`: register leave
* `3116`: register continue

## 11. Recommended frontend state model

### 11.1 Constants

```ts
export const MAX_SEAT = 8

export enum PlayerState {
  EMPTY = 0,
  VIEWER = 1,
  SITTING = 2,
  PLAYING = 3,
}

export enum GameState {
  WAITING = 0,
  PLAYING = 1,
  ENDING = 2,
}
```

### 11.2 Suggested store shape

```ts
type SeatPublicState = {
  chair: number
  playerState: 0 | 1 | 2 | 3
  nickName: string | null
  avatarUrl: string | null
  currentMoney: number
  reqQuitRoom?: boolean
  isChuong?: boolean
}

type MyPrivateState = {
  chair: number | null
  handCards: number[]
  cuocDanhBien: number[]
  cuocKeCua: number[]
  cuocGa: number
  cuocChuong: number
}

type MatchState = {
  roomId: number | null
  gameId: number | null
  moneyType: number | null
  moneyBet: number
  rule: number
  chuongChair: number | null
  ownerChair?: number | null
  gameState: 0 | 1 | 2
  gameAction: number
  isAutoStart: boolean
  countDownTime: number
  seats: SeatPublicState[]
  me: MyPrivateState
}
```

Principles:

* always build state by `chair`
* always maintain all 8 seats
* do not rely on packet order
* clearly separate public state and private state

## 12. Meaning of key variables

* `chair`: seat index `0..7`
* `uChair`: current user seat
* `chuongChair`: banker seat
* `ownerChair`: room owner
* `moneyBet`: base bet
* `moneyType`: currency type
* `rule`: room rule
* `gameId`: round id
* `roomId`: room id
* `gameState`: waiting / playing / ending
* `gameAction`: sub-phase in round
* `countDownTime`: server countdown time
* `playerState`: seat state
* `currentMoney`: current user money
* `reqQuitRoom`: request leave flag
* `handCards`: personal cards
* `cuocChuong`: bet with banker
* `cuocGa`: ga bet
* `cuocKeCua`: ke cua bet
* `cuocDanhBien`: danh bien bet

## 13. Game flow frontend must handle

```text
3118 JOIN_ROOM_SUCCESS
-> 3107 AUTO_START or wait for start
-> 3114 BET_PHASE
-> user sends bet command
-> 3105 DEAL_CARDS
-> 3101 OPEN_CARDS
-> 3103 END_GAME
-> 3123 RESET MATCH
```

Reconnect:

```text
reconnect
-> 3110 GAME_INFO
-> resync full state
```

## 14. Integration checklist

* perform HTTP/API login first to get `nickname` and `sessionKey`
* connect to correct `ws://.../websocket` or `wss://.../websocket`
* send core login with `controllerId=1`, `actionId=1`
* only join room after login success
* only send Bacay commands after `3118`
* use `3118` to initialize store
* use `3110` for full sync when reconnect
* always map players by `chair`

## 15. What belongs to frontend vs test/debug

Frontend integration should focus on:

* `wsUrl`
* `nickname`
* `sessionKey`
* join room information
* packets `3118`, `3110`, `3101..3123`

Test/debug focuses on:

* `BACAY_LOGIN_PACKET_HEX`
* `BACAY_JOIN_PACKET_HEX`
* replaying raw hex packets

If the frontend team is integrating the game, prioritize reading this document first.

```

:contentReference[oaicite:0]{index=0}
```
