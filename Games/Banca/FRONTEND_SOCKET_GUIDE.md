Here is your translated `.md` content (references removed, no additions or omissions):

---

# BanCa Frontend Socket Guide

This document is for frontend developers integrating the client socket into the BanCa game.

Principles of this document:

* Only record what is directly read from the current source.
* The underlying WebSocket protocol, login, authentication, and raw binary frame do not have full source in this repo, so they are not described in detail.
* Game-level commands of BanCa are in the range `3101..3126`.

## 1. Integration Scope

This repo clearly describes the BanCa game after the user has:

* successfully connected to the socket
* successfully logged in
* successfully joined a game room

Frontend should be separated into 2 layers:

1. `Core socket/game-room layer`

   * connect TCP/WebSocket
   * login
   * fetch game config if needed
   * join room/reconnect room
   * decode WebSocket base packet frame

2. `BanCa game layer`

   * handle commands `3101..3126`
   * build a 4-seat table
   * render fish in 2D/3D
   * send shooting actions, shooting results, lock fish, add money into game, leave table

## 2. Connection Endpoint

According to current configuration:

* TCP game: `21243`
* WebSocket: `21244`
* WebSocket SSL: `21246`
* Admin TCP: `21245`

If running Docker, default host mapping:

* TCP host: `21243`
* WebSocket host: `21244`
* WebSocket SSL host: `21246`
* Admin host: `21245`

## 3. General Flow

```text
Connect
-> Login
-> Request USER_INFO / GAME_CONFIG if needed
-> Join Game Room
-> Server calls FishServer.onGameUserEnter
-> Receive 3118 JOIN_ROOM_SUCCESS
-> Receive 3103 UPDATE_ROUND or 3122 UPDATE_ROUND_3D
-> Receive 3105 USER_JOIN_ROOM when others join
-> Game loop broadcasts 3124 GAME_STATE each tick
-> Client sends 3101 START_SHOOT
-> Client sends 3102 SHOOT_RESULT
-> Server broadcasts results via 3124 GAME_STATE
-> Client sends 3106 USER_EXIT
-> Receive 3125 UPDATE_MONEY when settling on exit
```

Key points:

* `3118 JOIN_ROOM_SUCCESS` is the bootstrap packet for the user.
* After `3118`, server immediately sends `3103 UPDATE_ROUND` (2D) or `3122 UPDATE_ROUND_3D` (3D).
* `3124 GAME_STATE` is the main realtime packet, sent every ~100ms.
* Some command classes exist but are not used; data is bundled into `3124 GAME_STATE`.

## 4. Frontend Constants

```ts
export const MAX_PLAYER = 4

export enum PlayerState {
  NO_PLAY = 0,
  PLAYING = 1,
}

export enum FishGameState {
  NORMAL_MAP = 0,
  PREPARE = 1,
  MATRIX_MAP = 2,
}

export enum FishGameType {
  GAME_2D = 0,
  GAME_3D = 1,
}

export enum FishCommand {
  START_SHOOT = 3101,
  SHOOT_RESULT = 3102,
  UPDATE_ROUND = 3103,
  ADD_FISH = 3104,
  USER_JOIN_ROOM = 3105,
  USER_EXIT = 3106,
  STATE_CHANGE = 3107,
  MATRIX_DATA = 3108,
  LOCK_FISH = 3109,
  JOIN_ROOM_SUCCESS = 3118,
  LEAVE_GAME = 3119,
  ADD_FISH_3D = 3120,
  ADD_SPHERE_3D = 3121,
  UPDATE_ROUND_3D = 3122,
  ADD_CIRCLE = 3123,
  GAME_STATE = 3124,
  UPDATE_MONEY = 3125,
  GET_MONEY_IN_GAME = 3126,
}
```

## 5. Recommended Frontend Store

```ts
type FishPath2D = {
  fishId: number
  fishType: number
  totalTime: number
  elapsedTime: number
  usingConstantVelocity: boolean
  points: Array<{ x: number; y: number }>
  splineType: number
}

type FishPath3D = {
  fishId: number
  fishType: number
  totalTime: number
  elapsedTime: number
  usingConstantVelocity: boolean
  pathExtensions: string
  parentPosition: { x: number; y: number; z: number }
  points: Array<{ x: number; y: number; z: number }>
}

type SeatState = {
  position: number
  userId: number
  nickName: string
  avatarUrl: string
  vip: number
  moneyInGame: number
  currentMoneyPreview?: number
  fishLockId: number
}

type BanCaState = {
  myPosition: number | null
  roomId: number | null
  moneyType: number | null
  roomType: 0 | 1 | null
  bets: number[]
  gameState: 0 | 1 | 2
  isGameFreezed: boolean
  fishes2D: Map<number, FishPath2D>
  fishes3D: Map<number, FishPath3D>
  seats: Map<number, SeatState>
}
```

Principles:

* Map seats by `position`.
* Map fish by `fishId`.
* `roomType=0` is 2D, `roomType=1` is 3D.
* `bets` should come from server.

## 6. Client Commands

### `3101 - START_SHOOT`

Payload:

* `bet: long`
* `whereTouch.x: float`
* `whereTouch.y: float`

Server:

* validate via `FishRule.verifyShoot`
* push to `shootRequestQueue`

### `3102 - SHOOT_RESULT`

Payload:

* `bet: long`
* `fishID: int`

Server:

* validate
* push to `shootResultRequestQueue`

### `3109 - LOCK_FISH`

Payload:

* `isLock: boolean`
* `fishID: int`

Server:

* set `fishLockID`
* broadcast to others

### `3126 - GET_MONEY_IN_GAME`

Payload:

* `money: long`

Server:

* freeze money if valid
* return success flag

### `3106 - USER_EXIT`

Server:

* call leave room

## 7. Server Commands

### `3118 - JOIN_ROOM_SUCCESS`

Bootstrap packet.

Payload:

* `position`
* `moneyType`
* `roomID`
* `roomType`
* `roomBets`
* `playerCount`
* player list

Notes:

* `nickName` appears twice
* `vip` = 0

### `3103 - UPDATE_ROUND`

2D round sync.

### `3122 - UPDATE_ROUND_3D`

3D round sync.

### `3124 - GAME_STATE`

Main realtime packet.

Includes:

* fish spawn
* shooting
* results
* player state

### `3105 - USER_JOIN_ROOM`

Broadcast when a player joins.

### `3106 - USER_EXIT`

Broadcast when a player leaves.

### `3107 - STATE_CHANGE`

Game state transition.

### `3109 - LOCK_FISH`

Broadcast lock/unlock.

### `3121 - ADD_SPHERE_3D`

3D matrix phase.

### `3123 - ADD_CIRCLE`

2D matrix phase.

### `3125 - UPDATE_MONEY`

Sent when leaving.

## 8. Game Config `3020`

Returns:

* `jsonConfig`

Includes:

* `prize`

## 9. Map Lifecycle

States:

* `0 NORMAL_MAP`
* `1 PREPARE`
* `2 MATRIX_MAP`

Timing:

* `300s`, `6.5s`, `120s`, `10s freeze`

## 10. Money Logic

Display:

* `moneyInGame = moneyStart + moneyInRoom`
* `moneyTamTinhForUser = currentMoney + moneyInRoom`

Rules:

* must have enough money to shoot
* bet must be valid
* win adds money

## 11. Important Notes

* `fishesAddedCount` may be `0`
* `fishID` may be `-1`
* Some commands exist but are unused
* Some command IDs have no handlers
* `roomType` depends on rule; default is 2D

---

