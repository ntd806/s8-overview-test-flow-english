
````md
# How to Run `player_test_flow-v1.sh`

This file describes the current flow of the script `player_test_flow-v1.sh`.

---

## 1. Goal

This script is used to test the Portal v1 flow:

```text
Get captcha
Register a new user
Login
Set nickname if missing
Get sessionKey
Get game config
````

Final required values:

```text
USERNAME
PASSWORD
NICKNAME
SESSIONKEY
```

You will use `NICKNAME + SESSIONKEY` to log in to the game socket.

---

## 2. Requirements

Make sure Portal v1 is running at:

```text
http://127.0.0.1:8081/api
```

Quick check:

```bash
curl -s 'http://127.0.0.1:8081/api?c=124'
```

If the response contains `id` and `img`, the service is working.

---

## 3. Run the Script

Make sure you are in the directory that contains the script:

```bash
chmod +x ./player_test_flow-v1.sh
./player_test_flow-v1.sh
```

---

## 4. Auto-generated Test Data

The script automatically generates:

```text
USERNAME = test + last 7 digits of timestamp
PASSWORD = 123456
NICKNAME = play_ + last 7 digits of timestamp
```

Example:

```text
USERNAME = test4812184
PASSWORD = 123456
NICKNAME = play_4812184
```

Constraints:

```text
USERNAME: letters + numbers, length 6–16
NICKNAME: letters + numbers + _, length 6–16
```

---

## 5. Runtime Flow

### Step 1: Get captcha

```bash
curl -s 'http://127.0.0.1:8081/api?c=124'
```

* Saves captcha image
* Prompts user to input the captcha

---

### Step 2: Register

```bash
curl -s "http://127.0.0.1:8081/api?c=1&un=$USERNAME&pw=$PASSWORD&cp=$CAPTCHA&cid=$CID"
```

Possible results:

```text
errorCode = 0     → success
errorCode = 1006  → user exists
errorCode = 115   → wrong captcha
errorCode = 101   → invalid username
```

---

### Step 3: Login

```bash
curl -s "http://127.0.0.1:8081/api?c=3&un=$USERNAME&pw=$PASSWORD"
```

Handling:

```text
success = true → login OK
errorCode = 2001 → no nickname yet
errorCode = 1001 → retry with MD5 password
```

---

### Step 4: Set Nickname (if needed)

```bash
curl -s "http://127.0.0.1:8081/api?c=5&un=$USERNAME&pw=$LOGIN_PASSWORD&nn=$NICKNAME"
```

Handling:

```text
success = true → OK
errorCode = 106 → retry with shorter nickname
errorCode = 1013 → nickname exists → login again
```

Fallback nickname:

```text
p + last 7 digits of timestamp
```

---

### Step 5: Get Game Config

```bash
curl -s 'http://127.0.0.1:8081/api?c=6&v=1&pf=web&did=test&vnt='
```

Purpose:

```text
Check available game host/port
```

---

### Step 6: Final Output

```text
USERNAME
PASSWORD
NICKNAME
SESSIONKEY
```

---

## 6. Typical Successful Flow

```text
Register → success
Login → requires nickname
Set nickname → success
SESSIONKEY returned
```

---

## 7. Common Errors

### 115 → Wrong captcha

→ Re-run and enter correct captcha

### 101 → Invalid username

→ Avoid custom invalid USERNAME

### 2001 → No nickname

→ Expected behavior

### 106 → Invalid nickname

→ Script auto retries

### 1013 → Nickname exists

→ Script logs in again

### 1001 → Login error

→ Retry with MD5

---

## 8. Using the Result

Example WebSocket:

```text
ws://127.0.0.1:21044
```

Use:

```text
nickname = NICKNAME
sessionKey = SESSIONKEY
```

---

## 9. Important Note

This script follows Portal v1 flow:

```text
c=124 → captcha
c=1   → register
c=3   → login
c=5   → set nickname
c=6   → config
```

This file describes only the v1 flow.