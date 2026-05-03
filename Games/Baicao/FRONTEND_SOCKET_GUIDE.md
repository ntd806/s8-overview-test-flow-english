Here is your translated `.md` content (references removed, no additions or omissions):

---

# Baicao Frontend Socket Guide

This document is for frontend developers integrating the client socket into the Baicao game.

## 1. Scope

This repo describes the Baicao game after the user has connected, logged in, and joined a room via the WebSocket/game-room layer.

This repo does NOT include full source for:

* WebSocket handshake/login protocol
* General join room command of core game-room
* Base packet frame of `BaseMsg`/`BaseCmd`
* Framework error envelope

Frontend should separate into 2 layers:

* Core socket layer: connect, login, join room, decode base frame.
* Baicao game layer: handle commands `3101..3123`.

## 2. Connection Endpoint

According to `config/server.xml`:

* TCP game: `21143`
* WebSocket: `21144`
* WebSocket SSL: `21146`
* Admin TCP: `21145`

If running Docker, host ports may be remapped in `docker-compose.yml` and `.env`.

## 3. General Flow

```text
Connect
-> Login
-> Join Room
-> Receive 3118 JOIN_ROOM_SUCCESS
-> Wait 3107 auto-start or send 3102 BAT_DAU
-> Receive 3114 MOI_DAT_CUOC
-> Send betting commands: 3109 / 3112 / 3104 / 3106 / 3108
-> Receive 3105 CHIA_BAI
-> Send 3101 MO_BAI
-> Receive 3101 MO_BAI broadcasts
-> Receive 3103 KET_THUC
-> Receive 3123 CMD_SEND_UPDATE_MATCH before next match
```

Key points:

* `3118` is the bootstrap packet when joining a table.
* `3110` is the full sync packet when reconnect/return.
* Seats are fixed index `0..7`; do not build UI based on compact lists.

## 4. Suggested FE State

```ts
export const MAX_SEAT = 8

export enum PlayerStatus {
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
  BETTING = 1,
  OPEN_CARD = 2,
}

export type SeatState = {
  chair: number
  playerStatus: PlayerStatus
  nickName: string
  avatarUrl: string
  currentMoney: number
  isChuong: boolean
  reqQuitRoom?: boolean
  cuocGa?: number
  cuocChuong?: number
}

export type MyPrivateState = {
  chair: number
  cards: number[]
  cuocDanhBien: number[]
  cuocKeCua: number[]
}

export type MatchState = {
  roomId: number
  gameId: number
  moneyType: number
  moneyBet: number
  rule: number
  chuongChair: number
  gameState: GameState
  gameAction: GameAction
  isAutoStart: boolean
  countDownTime: number
  seats: SeatState[]
  me: MyPrivateState
}
```

## 5. Client Commands

### `3101 - OPEN_CARD`

Custom payload: none.

Server:

* Set `gp.moBai = true`.
* Broadcast `3101` if player has cards.
* If all players opened cards → `countDown = 0`.

### `3102 - START`

Custom payload: none.

Server:

* If playable players >= 2 → `makeAutoStart(0)`.

### `3104 - REQUEST_SIDE_BET`

Payload:

* `chair: byte`
* `rate: byte`

Conditions:

* Both players are playing.
* Neither is banker.
* `rate` in `1..2`.
* Both have enough money.

Server:

* Send `3104` to target if valid.
* Else return `3104` to sender.

### `3106 - JOIN_BET`

Payload:

* `chair: byte`
* `rate: byte`

Conditions:

* Valid seat `0..7`.
* Both playing.
* Neither banker.
* Not already joined that seat.
* Enough money.

Server:

* Success → broadcast `3106`.
* Error → return `3106`.

### `3108 - ACCEPT_SIDE_BET`

Payload:

* `chair: byte`

Server:

* Set side bet for both players.
* Send `3108` to both.

### `3109 - PLACE_BET`

Payload:

* `rate: byte`

Conditions:

* Player is playing.
* Not banker.
* Banker is active.
* `rate` in `1..4`.
* Not already bet.
* Enough money.

Server:

* Success → broadcast `3109`.
* Error → return `3109`.

### `3111 - REGISTER_LEAVE`

Server:

* If playing → toggle `reqQuitRoom` and broadcast.
* Else → leave room.

### `3112 - JOIN_GA`

Conditions:

* `playingCount > 2`
* Player is playing
* Not banker
* Not already joined
* Enough money

Server:

* Success → broadcast `3112`
* Error → return `3112`

### `3115 - CHEAT_CARDS`

Payload:

* `isCheat: boolean`
* `firstChair: byte`
* `cards: byte[]`

Only works if cheat mode enabled.

### `3116 - REGISTER_CONTINUE`

Server:

* Set `gp.choiTiepVanSau = true`.

## 6. Server Commands

### `3118 - JOIN_ROOM_SUCCESS`

Used to build initial table UI.

### `3110 - TABLE_INFO`

Used when reconnecting.

### `3107 - AUTO_START`

Used to show/hide countdown.

### `3114 - BET_PHASE`

`countDownTime = 4 * playingCount`

### `3105 - DEAL_CARDS`

Private per player.

### `3101 - OPEN_CARD`

Broadcast.

Card types:

* `0`: normal
* `1`: nine
* `2`: face cards
* `3`: triple
* `4`: invalid

### `3103 - END_GAME`

Contains full result + settlement.

### `3109 - PLACE_BET`

Note: error field may not exist in payload.

### `3112 - JOIN_GA`

`tienVaoGa = 3 * moneyBet`

### `3104 - REQUEST_SIDE_BET`

### `3108 - ACCEPT_SIDE_BET`

Do NOT rely on `rate`.

### `3106 - JOIN_BET`

### `3113 - CHANGE_BANKER`

### `3117 - UPDATE_OWNER_ROOM`

### `3119 - LEAVE_GAME`

### `3120 - KICK_FROM_ROOM`

Reasons:

* `1`: insufficient funds
* `2`: maintenance

### `3121 - NEW_USER_JOIN`

### `3122 - JACKPOT`

### `3123 - UPDATE_MATCH`

Sent before next round.

## 7. Cards & Rules

Card ID:

* `id = (number - 1) * 4 + suit`
* `number = id / 4 + 1`
* `suit = id % 4`

Suits:

* `0`: spade
* `1`: club
* `2`: heart
* `3`: diamond

Numbers:

* `1`: A
* `2..10`
* `11`: J
* `12`: Q
* `13`: K

Scoring:

* J/Q/K = 10
* Total % 10

Hand types:

* `0`: normal
* `1`: nine
* `2`: face
* `3`: triple

Comparison:

* Triple ×4
* Face ×3
* Nine ×2
* Normal ×1

Jackpot:

* J♦ Q♦ K♦

## 8. UI Handling by Phase

`gameState = 0`

* Waiting room
* Can start game (`3102`)
* Track `3107`

`gameState = 1`, `gameAction = 1`

* Betting phase
* Use: `3109`, `3112`, `3104`, `3106`, `3108`

`gameState = 1`, `gameAction = 2`

* Cards dealt
* Receive `3105`
* Allow `3101`

`gameState = 2`

* Show result `3103`
* Wait `3123`

---
