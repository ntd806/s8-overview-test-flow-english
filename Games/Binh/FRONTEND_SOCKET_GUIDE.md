Here is your translated `.md` content (references removed, no additions or omissions):

---

# Binh Frontend Socket Guide

This document is specifically for frontend developers integrating the client socket into the `Binh` game.

Objectives:

* Understand the correct game flow based on current code.
* Know which packets are received and when.
* Know which packets are private and which are broadcast.
* Have enough detail to build frontend store/state.

This document follows the current source in the repo, not assumptions from legacy clients.

## 1. Scope to Understand Immediately

This repo clearly describes the `Binh` game after the user has:

* successfully connected to the socket
* successfully logged in
* successfully joined a room

This repo does NOT include full source for:

* BitZero handshake/login protocol
* base packet frame
* core game-room join command
* base error envelope of `BaseMsg`

Therefore frontend should split into 2 layers:

1. `Core socket layer`

   * connect
   * login
   * join room
   * decode base packet frame

2. `Binh game layer`

   * handle commands `3101..3123`
   * update game store/UI

## 2. Connection Endpoint

In this repo, bind address and ports are not hard-coded but taken from environment variables in template:

* TCP game: `21343`
* WebSocket: `21344`
* WebSocket SSL: `21346`
* Admin TCP: `21345`

If running Docker, host ports depend on compose file.

## 3. General Flow (Actual Game Flow)

```text
Connect
-> Login
-> Join Room
-> Receive 3118 JOIN_ROOM_SUCCESS
-> Wait auto-start or send 3102 START
-> Receive 3107 AUTO_START
-> Receive 3105 DEAL_CARDS
-> Send 3101 BINH_SO_CHI or 3106 BAO_BINH
-> Optionally send 3108 REORDER
-> Receive 3103 END_GAME
-> Receive 3123 CMD_SEND_UPDATE_MATCH
```

Key points:

* Only send `Binh` commands after successfully joining room.
* Treat `3118` as the initial bootstrap packet.
* Treat `3110` as the most complete sync/reconnect packet.
* After dealing cards, sorting phase runs at `gameAction = 2`.

## 4. Suggested FE State Model

### 4.1 Basic Constants

```ts
export const MAX_SEAT = 4

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

export enum GameAction {
  NONE = 0,
  DEALING = 1,
  SORTING = 2,
  SHOW_RESULT = 3,
}
```

### 4.2 Recommended Store Structure

```ts
type SeatPublicState = {
  chair: number
  playerState: 0 | 1 | 2 | 3
  nickName: string | null
  avatarUrl: string | null
  userId?: number | null
  currentMoney: number
  reqQuitRoom?: boolean
  soChi?: boolean
}

type MyPrivateState = {
  chair: number | null
  handCards: number[]
}

type MatchResultItem = {
  chair: number
  maubinhType: number
  chi1: number[]
  chi2: number[]
  chi3: number[]
  moneyInChi: number[]
  moneyAt: number
  moneyCommon: number
  moneySapTong: number
  currentMoney: number
}

type MatchState = {
  roomId: number | null
  gameId: number | null
  moneyType: number | null
  moneyBet: number
  rule: number
  gameState: 0 | 1 | 2
  gameAction: 0 | 1 | 2 | 3
  isAutoStart: boolean
  countDownTime: number
  seats: SeatPublicState[]
  me: MyPrivateState
  endGameResults?: MatchResultItem[]
}
```

Principles:

* Always build state by `chair`.
* Do not rely on packet order.
* Empty seats must still exist in state.
* Only the receiving player always has their own cards during gameplay.

## 5. Key FE Variables

`chair`

* seat index `0..3`

`uChair`

* current user’s seat
* from `3118`

`gameState`

* `0`: waiting
* `1`: playing
* `2`: ended

`gameAction`

* `0`: none
* `1`: dealing
* `2`: sorting
* `3`: show result

`countDownTime`

* authoritative countdown from server

`moneyType`

* currency type

`moneyBet`

* base bet

`rule`

* room rule (0 or 1)

`playerState`

* `0`: empty
* `1`: viewer
* `2`: sitting
* `3`: playing

`soChi`

* whether player finished sorting

`reqQuitRoom`

* flag to leave after round

## 6. Client Commands

### `3101 - BINH_SO_CHI`

Payload:

* `chi1`
* `chi2`
* `chi3`

### `3102 - START`

* no payload

### `3104 - AUTO_SORT`

Payload:

* `chi1`
* `chi2`
* `chi3`

### `3106 - BAO_BINH`

* no payload

### `3108 - REORDER`

* no payload

### `3111 - REGISTER_LEAVE`

* no payload

### `3115 - CHEAT_CARDS`

Payload:

* `isCheat`
* `cards`

### `3116 - REGISTER_CONTINUE`

* no payload

## 7. Server Commands

### `3118 - JOIN_ROOM_SUCCESS`

Bootstrap packet.

### `3110 - GAME_INFO`

Full sync packet.

Notes:

* During `gameState == 1`, only self sees hand cards.
* During `gameState == 2`, all hands are visible.

### `3107 - AUTO_START`

### `3105 - DEAL_CARDS`

Private packet.

### `3103 - END_GAME`

Contains result list.

Notes:

* Sent per player with perspective-specific results.
* Viewers receive separate version.

### `3101 - BINH_SO_CHI`

Broadcast success.

### `3108 - REORDER`

Broadcast.

### Player Events

`3121 - NEW_USER_JOIN`

`3119 - LEAVE_GAME`

`3111 - REGISTER_LEAVE`

`3117 - UPDATE_OWNER_ROOM`

`3120 - KICK_FROM_ROOM`

`3122 - JACKPOT`

`3123 - UPDATE_MATCH`

## 8. Actual Packet Order per Round

1. `gameState = 0`
2. Auto-start → `3107`
3. Countdown → start → `gameState = 1`, `gameAction = 1`
4. Deal cards → `3105`
5. Switch to `gameAction = 2`, countdown = 66
6. Players send `3101` or `3106`
7. All sorted or timeout → `endGame()`
8. Send `3103`, set `gameState = 2`
9. Countdown → `3123`, reset to `gameState = 0`

## 9. Rule Handling

Rules:

* `0`
* `1`

Frontend should:

* store rule
* display if needed
* trust server result `3103`

## 10. What FE Should NOT Assume

* Do not infer others’ cards during `gameState = 1`
* Do not calculate results client-side
* Do not rely on payload-only error detection
* Do not assume fixed ports

## 11. Useful Files for Debug

* game server
* game manager
* player
* command definitions
* send/receive command folders

---