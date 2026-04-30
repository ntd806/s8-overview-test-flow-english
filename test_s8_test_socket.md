````md
# How to Use `NICKNAME` + `SESSIONKEY` with s8-test-socket

This guide explains how to use `NICKNAME` and `SESSIONKEY` from Portal v1  
to test the game WebSocket connection using `s8-test-socket`.

---

## 1. Goal

Use `s8-test-socket` to test:

```text
Connect to game WebSocket
Send login packet (nickname + sessionKey)
Verify login success
Send additional actions (join room, gameplay, etc.)
````

---

## 2. Get NICKNAME and SESSIONKEY

Run the v1 script:

```bash
chmod +x ./player_test_flow-v1.sh
./player_test_flow-v1.sh
```

You will get:

```text
USERNAME
PASSWORD
NICKNAME
SESSIONKEY
```

Example:

```text
NICKNAME   = play_4812184
SESSIONKEY = eyJuaWNrbmFtZSI6InBsYXlfNDgxMjE4NCIs...
```

---

## 3. Run s8-test-socket

Clone and run:

```bash
git clone git@github.com:ntd806/s8-test-socket.git \
&& cd s8-test-socket \
&& docker compose up -d --build
```

Open the UI:

```text
http://127.0.0.1:3000/
```

---

## 4. Web UI Test Flow

```text
1. Select a game
2. Input host
3. Input port
4. Set WS Path = /websocket
5. Click Connect
6. Paste SESSIONKEY
7. Fill NICKNAME (or auto-fill)
8. Generate Login Hex
9. Click Login
10. Send additional packets if needed
```

---

## 5. Using SESSIONKEY

In the UI:

```text
Session Key → paste SESSIONKEY
Nickname    → paste NICKNAME (recommended)
```

Auto behavior:

```text
If nickname is empty → system tries to decode from SESSIONKEY
```

---

## 6. Login Hex Format (Auto-generated)

```text
00 00 00
01
00 01
00 01
<nickname>
<sessionKey>
```

Meaning:

```text
controller id
request id
data command
nickname string
sessionKey string
```

👉 No need to build manually (tool handles it)

---

## 7. Local WebSocket Ports

```text
Bacay       → 21044
Baicao      → 21144
BanCa       → 21244
Binh        → 21344
Caro        → 21444
Coup        → 21544
Lieng       → 21644
Poker       → 21744
Sam         → 21944
SlotMachine → 22044
Tienlen     → 22144
Xizach      → 22244
minigame    → 22344
xocdia      → 22444
```

Host:

```text
127.0.0.1
```

Example:

```text
ws://127.0.0.1:21044/websocket
```

---

## 8. Quick Bacay Test

```text
Step 1 → Run v1 script
Step 2 → Open http://127.0.0.1:3000/
Step 3 → Select Bacay
Step 4 → Host = 127.0.0.1
Step 5 → Port = 21044
Step 6 → Path = /websocket
Step 7 → Connect
Step 8 → Paste SESSIONKEY + NICKNAME
Step 9 → Login
```

Expected:

```text
WebSocket connected
Binary response received
Connection stays open
```

---

## 9. After Login

You can test:

```text
Join Room
Gameplay actions
Reconnect
Leave room
```

---

## 10. Pass Criteria

```text
WS connects successfully
Login packet works
Server responds
Connection stays alive
Further actions work
```

---

## 11. Common Issues

### Cannot connect

* Game container not running
* Wrong port
* Wrong host
* Wrong path

---

### Login failed

* Invalid SESSIONKEY
* Wrong NICKNAME
* Wrong port

---

### Timeout

* Invalid login packet
* Expired sessionKey
* Wrong WS path

---

## 12. Important Notes

```text
Portal → provides sessionKey
Socket → handles real gameplay connection
```

This is a **binary WebSocket**, not REST API.

```

---