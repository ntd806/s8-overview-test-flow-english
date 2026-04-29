# How to Use `NICKNAME` + `SESSIONKEY` with `s8-test-socket`

This file explains how to get `NICKNAME` and `SESSIONKEY` from Portal v1, then use them to test the game socket connection in this project:

Clone
git clone git@github.com:ntd806/s8-test-socket.git \
&& cd s8-test-socket \
&& docker compose up -d --build

## 1. Goal

Use `s8-test-socket` to visually test these steps:

```text
Open a WebSocket connection to the game
Send a login packet with nickname + sessionKey
Confirm that login succeeds
Send extra join-room / action hex packets on the same socket
```

## 2. Get `NICKNAME` and `SESSIONKEY`

First run:

```bash
cd /root/ && ./player_test_flow-v1.sh
```

The final values you need are:

```text
USERNAME   = ...
PASSWORD   = 123456
NICKNAME   = ...
SESSIONKEY = ...
```

Example:

```text
NICKNAME   = play_4812184
SESSIONKEY = eyJuaWNrbmFtZSI6InBsYXlfNDgxMjE4NCIs...
```

Then use that same `NICKNAME` and `SESSIONKEY` to log in to the game socket.

## 3. Run `s8-test-socket`

Go to the tool directory:

```bash
git clone git@github.com:ntd806/s8-test-socket.git \
&& cd s8-test-socket \
&& docker compose up -d --build
```

Open the web UI:

```text
http://127.0.0.1:3000/
```

## 4. Correct Test Flow in the Web UI

The web tester currently uses a real binary WebSocket on this path:

```text
/websocket
```

Standard interaction flow:

1. Select a game.
2. Fill in `host`.
3. Fill in `port`.
4. Keep `WS Path=/websocket`.
5. Click `Connect`.
6. Paste `SESSIONKEY`.
7. If the `Nickname` field is empty, the app auto-fills the nickname from the payload inside `SESSIONKEY`.
8. You can click `Generate Login Hex`, or let the app generate it automatically after connect.
9. Click `Login`.
10. If you want to continue testing, paste `Join Room Hex` or `Action Hex` and send it on the same socket.

## 5. How to Use `SESSIONKEY`

In the `s8-test-socket` UI:

```text
Session Key field -> paste the SESSIONKEY from player_test_flow-v1.sh
Nickname field    -> paste NICKNAME if you want, or leave it empty so the app auto-fills it from SESSIONKEY
```

The tool currently has this logic:

```text
If nickname is empty and sessionKey can decode payload.nickname
the app auto-fills the nickname
```

So the safest approach is:

```text
Paste both SESSIONKEY and NICKNAME
```

## 6. What Is the Auto-Generated Login Hex?

The web tester auto-builds a BitZero WebSocket login frame in this format:

```text
00 00 00
01
00 01
00 01
<nickname string>
<sessionKey string>
```

Meaning:

```text
00 00 00 -> WS prefix ignored by BitZero WebSocketCodec
01       -> controller id
00 01    -> login request id
00 01    -> login dataCmd id
nickname -> string with a 2-byte length prefix
sessionKey -> string with a 2-byte length prefix
```

Normally you do not need to build it manually because the app already generates `Login Hex`.

## 7. Local Game Ports for WS Testing

Current local WS ports:

```text
Bacay       -> 21044
Baicao      -> 21144
BanCa       -> 21244
Binh        -> 21344
Caro        -> 21444
Cotuong     -> 22544
Coup        -> 21544
Lieng       -> 21644
Poker       -> 21744
PokerTour   -> 21844
Sam         -> 21944
SlotMachine -> 22044
Tienlen     -> 22144
Xizach      -> 22244
minigame    -> 22344
xocdia      -> 22444
```

The local host is usually:

```text
127.0.0.1
```

Example for testing Bacay:

```text
Host    = 127.0.0.1
Port    = 21044
WS Path = /websocket
URL     = ws://127.0.0.1:21044/websocket
```

## 8. Quick Bacay Test Example

### Step 1

Get `NICKNAME` and `SESSIONKEY` from:

```bash
./player_test_flow-v1.sh
```

### Step 2

Open:

```text
http://127.0.0.1:3000/
```

### Step 3

Select:

```text
Game    = Bacay
Host    = 127.0.0.1
Port    = 21044
Path    = /websocket
```

### Step 4

Click:

```text
Connect
```

Expected result:

```text
WebSocket opened
or the summary says it connected to ws://127.0.0.1:21044/websocket
```

### Step 5

Paste:

```text
Session Key = <SESSIONKEY>
Nickname    = <NICKNAME>
```

### Step 6

Click:

```text
Generate Login Hex
Login
```

Expected result:

```text
Binary response is returned
No timeout
The socket is not closed immediately after login
```

## 9. What to Test After Login

After the socket login succeeds, you can continue testing:

```text
Join Room Hex
Action Hex
Reconnect flow
Leave room
```

These packets must be sent on the same logged-in socket.

## 10. Basic Pass Criteria

A game is considered minimally passing when:

```text
WS connect succeeds
The login packet is sent successfully
There is a response from the server
The socket is not closed immediately
You can send additional join-room or action packets
```

## 11. Common Issues

### Cannot connect

Check:

```text
Is the game container running?
Is the WS port correct?
Is the host correct?
Is the WS path really /websocket?
```

### Connect works but login fails

Check:

```text
Was SESSIONKEY just retrieved from Portal?
Does NICKNAME belong to the SESSIONKEY user?
Is that the correct WS port for the game?
Are controller/request/dataCmd correct in the Login Hex?
```

### The app says WS config is missing

Meaning:

```text
That game does not have <GAME>_WS_PORT or <GAME>_WSS_PORT in the s8-test-socket .env
```

The browser tester does not use `GAME_PORT` TCP to open WebSocket.

### Timeout after sending login

Check:

```text
Is the login packet in the correct format?
Is SESSIONKEY still valid?
Is the socket server receiving the correct path /websocket?
```

## 12. Important Notes

`s8-test-socket` is testing a real binary WebSocket flow, not a REST API.

So:

```text
Portal is used to get the session
The game socket is used to connect/login/join/action
```

The `SESSIONKEY` from Portal v1 is currently the most important piece of data for entering the game socket in this tool.
