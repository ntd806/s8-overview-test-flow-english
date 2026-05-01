````md
# SOCKET INTEGRATION INFORMATION FOR THE GAME

**Folder:** Games

# TEST OVERVIEW

This file is the high-level guide for which documents to read first and the correct order to run tests.

---

## 1. Goal

Recommended testing order:

```text
Legacy API v1
Game socket
API v2
````

Reason:

```text
Legacy API v1 is used to create a user and obtain the sessionKey
The game socket requires NICKNAME + SESSIONKEY from v1
API v2 should be tested only after Portal and socket are confirmed working
```

---

## 2. Reading & Execution Flow

### Step 1

Read:

```text
player_test_flow.md
```

---

### Step 2

Run the v1 test script:

```bash
chmod +x ./player_test_flow-v1.sh
./player_test_flow-v1.sh
```

Expected result:

```text
NICKNAME
SESSIONKEY
```

---

### Step 3

Read:

```text
test_s8_test_socket.md
```

---

### Step 4

Run the socket testing tool:

```bash
git clone git@github.com:ntd806/s8-test-socket.git \
&& cd s8-test-socket \
&& git checkout ui \
&& cp .env.example .env \
&& docker compose up -d --build
```

Then open:

```text
http://127.0.0.1:3000/
```

---

### Step 5

Read:

```text
test_v2_full_flow.md
```

---

### Step 6

Run the v2 full flow script:

```bash
chmod +x ./test_v2_full_flow.sh
./test_v2_full_flow.sh
```

---

## 3. Recommended Execution Order

```text
1. Run player_test_flow-v1.sh
2. Get NICKNAME + SESSIONKEY
3. Use s8-test-socket to test game connection and login
4. Run test_v2_full_flow.sh
```

---

## 4. Quick Test Options

### Only test Legacy API v1

```bash
./player_test_flow-v1.sh
```

---

### Only test Game Socket

Requirement:

```text
You must already have NICKNAME + SESSIONKEY
```

---

### Only test API v2

```bash
./test_v2_full_flow.sh
```

---

## 5. Short Summary

```text
player_test_flow.md
→ player_test_flow-v1.sh
→ test_s8_test_socket.md
→ http://127.0.0.1:3000/
→ test_v2_full_flow.md
→ test_v2_full_flow.sh
```

---

## 6. Notes

* All commands assume you are already in the correct working directory.
* No absolute paths are required.
* Scripts are portable and can run in any environment.

```
```
