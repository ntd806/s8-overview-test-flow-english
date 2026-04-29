# Test Overview
This file is the high-level guide for which documents to read first and which order to run the tests in.

## 1. Goal

Recommended order for testing the whole system:

```text
Legacy API v1
Game socket
API v2
```

Reason:

```text
Legacy API v1 helps create a user, log in, and get the sessionKey
The game socket needs nickname + sessionKey from API v1
API v2 should be tested after Portal and the game socket are confirmed working
```

## 2. Reading Order

### Step 1

Read:

[testv1.md]

Purpose:

```text
Understand the Portal v1 flow
Know how to run player_test_flow-v1.sh
Know how to get USERNAME, NICKNAME, and SESSIONKEY
```

### Step 2

Run:

```bash
cd root/ && ./player_test_flow-v1.sh
```

Expected result:

```text
NICKNAME
SESSIONKEY
```

### Step 3

Read:

[test_s8_test_socket.md]

Purpose:

```text
Know how to use NICKNAME + SESSIONKEY
Know how to open s8-test-socket
Know how to connect and log in to the game socket
```

### Step 4

Run the tool:

```bash
git clone git@github.com:ntd806/s8-test-socket.git \
&& cd s8-test-socket \
&& docker compose up -d --build
```

Then open:

```text
http://127.0.0.1:3000/
```

### Step 5

Read:

[test_v2_full_flow.md]

Purpose:

```text
Understand the API v2 flow
Know how to run test_v2_full_flow.sh
Know the auth token, create account, balance, deposit, launch, and withdraw steps
```

### Step 6

Run:

```bash
cd root && ./test_v2_full_flow.sh
```

## 3. Recommended Execution Order

```text
1. Run player_test_flow-v1.sh
2. Get NICKNAME + SESSIONKEY
3. Use s8-test-socket to test game connect/login
4. Run test_v2_full_flow.sh
```

## 4. If You Only Want a Quick Test

### Only test legacy API v1

Read:

[testv1.md]

Run:

```bash
./player_test_flow-v1.sh
```

### Only test the game socket

Read:

[test_s8_test_socket.md]

Requirement:

```text
You must have NICKNAME + SESSIONKEY first
```

### Only test API v2

Read:

[test_v2_full_flow.md]

Run:

```bash
./test_v2_full_flow.sh
```

## 5. Short Conclusion

If you want to test in the correct order, follow this path:

```text
testv1.md
-> player_test_flow-v1.sh
-> test_s8_test_socket.md
-> http://127.0.0.1:3000/ (s8-test-socket)
-> test_v2_full_flow.md
-> test_v2_full_flow.sh
```
