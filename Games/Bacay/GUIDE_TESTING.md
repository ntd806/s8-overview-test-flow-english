# Bacay Frontend Socket Guide

This document is intended for frontend developers integrating the Bacay game client via socket.

## Objectives

* Understand the actual game flow based on current code.
* Know which packets are received and when.
* Distinguish between private packets and broadcast packets.
* Have enough detail to build frontend state/store.

This document strictly follows the current repository source, not assumptions from older clients.

---

## 1. Scope to Understand First

This repo clearly describes the Bacay game after the user has:

* successfully connected socket
* successfully logged in
* successfully joined a room

The repo does NOT include full source for:

* BitZero handshake/login protocol
* base packet frame
* join room command from core game-room
* base error envelope (`BaseMsg`)

👉 Frontend should separate into 2 layers:

### 1. Core socket layer

* connect
* login
* join room
* decode base packet frame

### 2. Bacay game layer

* handle commands `3101..3123`
* update game store/UI

---

## 2. Connection Endpoints

Based on current config:

* TCP game: `21043`
* W-ebSocket: `21044`
* WebSocket SSL: `21046`
* Admin TCP: `21045`

---

## 3. Correct Game Flow

```text
Connect
-> Login
-> Join Room
-> Receive 3118 JOIN_ROOM_SUCCESS
-> Wait auto-start or send 3102 BAT_DAU
-> Receive 3114 MOI_DAT_CUOC
-> Send betting commands
-> Receive 3105 CHIA_BAI
-> Send 3101 MO_BAI
-> Receive 3103 KET_THUC
-> Receive/handle 3123 CMD_SEND_UPDATE_MATCH
```

Important:

* Only send Bacay commands after joining room successfully.
* Treat `3118` as the first bootstrap packet.
* Treat `3110` as the strongest full-sync packet.

---

## 4. Recommended Frontend State Model

### 4.1 Constants

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

---

### 4.2 Store Structure

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

* Always build state based on `chair`
* Do NOT rely on packet order
* Do NOT assume compact player arrays
* Empty seats must still exist

---

### 4.3 Key Field Meanings (Condensed)

* `chair`: seat index (0–7), primary mapping key
* `uChair`: current user’s seat
* `chuongChair`: banker seat
* `ownerChair`: room owner seat
* `moneyBet`: base bet amount
* `moneyType`: currency type (0: xu, 1: vin)
* `rule`: room rule
* `gameId`: match ID
* `roomId`: room ID
* `gameState`: lifecycle (waiting / playing / ending)
* `gameAction`: sub-phase (betting / opening)
* `countDownTime`: authoritative server timer
* `isAutoStart`: auto-start flag
* `playerState`: seat status
* `currentMoney`: player balance
* `reqQuitRoom`: exit request flag
* `handCards`: private cards
* `cuocChuong`: bet vs banker
* `cuocGa`: side bet
* `cuocKeCua`: side alignment bets
* `cuocDanhBien`: duel bets

---

## 5. Frontend Source of Truth

Key packets:

* `3118` → initial state (join)
* `3110` → full sync (reconnect)
* `3103` → personal result
* `3123` → reset for next match

---

## 6. Game Command List

```ts
export enum BacayCmd {
  MO_BAI = 3101,
  BAT_DAU = 3102,
  KET_THUC = 3103,
  YEU_CAU_DANH_BIEN = 3104,
  CHIA_BAI = 3105,
  KE_CUA = 3106,
  TU_DONG_BAT_DAU = 3107,
  DONG_Y_DANH_BIEN = 3108,
  DAT_CUOC = 3109,
  THONG_TIN_BAN_CHOI = 3110,
  DANG_KY_THOAT_PHONG = 3111,
  VAO_GA = 3112,
  DOI_CHUONG = 3113,
  MOI_DAT_CUOC = 3114,
  CHEAT_CARDS = 3115,
  DANG_KY_CHOI_TIEP = 3116,
  UPDATE_OWNER_ROOM = 3117,
  JOIN_ROOM_SUCCESS = 3118,
  LEAVE_GAME = 3119,
  NOTIFY_KICK_FROM_ROOM = 3120,
  NEW_USER_JOIN = 3121,
  NOTIFY_USER_GET_JACKPOT = 3122,
  CMD_SEND_UPDATE_MATCH = 3123,
}
```

---

## 7. Client → Server Commands (Summary)

* `3102` → start game
* `3109` → place bet
* `3112` → join side pot
* `3106` → side alignment bet
* `3104` → request duel
* `3108` → accept duel
* `3101` → reveal cards
* `3111` → request exit
* `3116` → continue next round

---

## 8. Server → Client (Key Handling)

### Important Packets

* `3118` → JOIN_ROOM_SUCCESS → bootstrap state
* `3121` → NEW_USER_JOIN → update seat only
* `3110` → GAME_INFO → full sync (strongest)
* `3114` → BETTING PHASE
* `3105` → DEAL CARDS (private)
* `3101` → REVEAL RESULT (broadcast)
* `3103` → END GAME (personalized)
* `3123` → RESET MATCH
* `3119` → USER LEAVE
* `3113` → CHANGE BANKER
* `3120` → KICK
* `3122` → JACKPOT

---

## 9. Full Frontend Flow

### Join Room

```text
-> 3118
-> possibly 3121 updates
```

### Waiting

```text
-> 3107 auto-start OR 3102 manual start
```

### Betting

```text
-> 3114
-> send betting commands
```

### Deal & Reveal

```text
-> 3105
-> 3101 actions
```

### End Game

```text
-> 3103
-> 3123 reset
```

### Reconnect

```text
-> 3110
-> possibly 3103
```

---

## 10. Frontend Rules

### UI Rules

* Show BET only when PLAYING
* Hide actions for banker when needed
* VAO_GA only when players > 2
* KE_CUA / DANH_BIEN must validate targets
* MO_BAI only after cards dealt

---

### State Phases

```ts
type UiPhase =
  | "idle"
  | "joined"
  | "auto_start"
  | "betting"
  | "dealt"
  | "opening"
  | "ending"
```

---

### Optimistic Update

* Avoid relying on optimistic updates
* Always confirm with server response

---

## 11. Frontend Checklist

* Parse by `cmdId`
* Distinguish private vs broadcast
* Always keep 8 seats
* Separate public/private state
* Use:

  * `3118` → init
  * `3110` → reconnect
  * `3123` → reset
* Handle personalized result (`3103`)

---

## 12. Packet Direction Summary

| Cmd  | Name          | Receiver        |
| ---- | ------------- | --------------- |
| 3118 | join success  | self            |
| 3121 | new user      | others          |
| 3110 | game info     | self            |
| 3107 | auto start    | broadcast       |
| 3114 | betting       | players         |
| 3109 | bet           | broadcast/local |
| 3112 | side pot      | broadcast/local |
| 3106 | side bet      | broadcast/local |
| 3104 | duel request  | target only     |
| 3108 | duel accept   | 2 players       |
| 3105 | deal cards    | private         |
| 3101 | reveal        | broadcast       |
| 3103 | end           | private         |
| 3123 | update match  | per player      |
| 3119 | leave         | broadcast       |
| 3113 | change banker | broadcast       |
| 3120 | kick          | self            |
| 3122 | jackpot       | broadcast       |

---
