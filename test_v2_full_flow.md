````md
# How to Run `test_v2_full_flow.sh`

This file describes the flow of the script `test_v2_full_flow.sh`.

---

## 1. Goal

This script tests the full Portal API v2 flow:

```text
Get access token
Create account
Check balance
Deposit
Launch game
Withdraw
Check final balance
````

Expected final result:

```text
FULL FLOW PASSED
USER = ...
FINAL_BALANCE = DEPOSIT_AMOUNT - WITHDRAW_AMOUNT
```

---

## 2. Requirements

Make sure Portal v2 is running at:

```text
http://127.0.0.1:8081
```

Make sure the auth endpoint works:

```text
POST /api/v2/4001
```

---

## 3. Run the Script

Make sure you are in the directory that contains the script:

```bash
chmod +x ./test_v2_full_flow.sh
./test_v2_full_flow.sh
```

---

## 4. Configuration

Default values:

```text
BASE            = http://127.0.0.1:8081
OP              = default
API_KEY         = default_secret_key
SECRET          = default_secret_key
CURRENCY        = VND
GAME_ID         = bacay
DEPOSIT_AMOUNT  = 10000
WITHDRAW_AMOUNT = 3000
```

The script auto-generates:

```text
USER         = curlv2_<timestamp>
TXN          = txn_<USER>
WITHDRAW_TXN = txn_<USER>_w
```

Example custom run:

```bash
BASE=http://127.0.0.1:8081 \
OP=default \
API_KEY=default_secret_key \
SECRET=default_secret_key \
GAME_ID=bacay \
DEPOSIT_AMOUNT=20000 \
WITHDRAW_AMOUNT=5000 \
./test_v2_full_flow.sh
```

---

## 5. Runtime Flow

### Step 1: Get Access Token

```text
POST /api/v2/4001
```

Request:

```json
{
  "operatorCode": "default",
  "apiKey": "default_secret_key",
  "timestamp": 123456789,
  "signature": "HMAC_SHA256"
}
```

Signature:

```text
HMAC-SHA256(secret, operatorCode + apiKey + timestamp)
```

Expected:

```json
{
  "success": true,
  "data": {
    "accessToken": "...",
    "refreshToken": "..."
  }
}
```

---

### Step 2: Create Account

```text
POST /api/v2/4011
Authorization: Bearer <accessToken>
```

Body:

```json
{
  "operatorCode": "default",
  "username": "curlv2_<timestamp>",
  "currency": "VND"
}
```

---

### Step 3: Check Balance

```text
POST /api/v2/4012
```

Expected:

```text
balance = 0
```

---

### Step 4: Deposit

```text
POST /api/v2/4021
```

Body:

```json
{
  "type": "DEPOSIT",
  "amount": 10000
}
```

---

### Step 5: Launch Game

```text
POST /api/v2/4031
```

Expected:

```json
{
  "launchUrl": "...",
  "sessionToken": "..."
}
```

---

### Step 6: Withdraw

```text
POST /api/v2/4021
```

```json
{
  "type": "WITHDRAW",
  "amount": 3000
}
```

---

### Step 7: Final Balance

```text
POST /api/v2/4012
```

Validation:

```text
EXPECTED = DEPOSIT - WITHDRAW
ACTUAL   = API response
```

---

## 6. Success Output

```text
FULL FLOW PASSED
USER: curlv2_<timestamp>
FINAL_BALANCE: 7000
```

---

## 7. Common Errors

### Auth failed

* Wrong API_KEY / SECRET
* Invalid signature

---

### Cannot get accessToken

* Wrong response format
* API down

---

### Create account failed

* Invalid token
* DB issue

---

### Deposit / Withdraw failed

* Duplicate transaction
* User not found

---

### Balance mismatch

* API inconsistency
* Transaction not applied

---

## 8. Notes

* This script tests **API v2 only**
* Does NOT use captcha
* Does NOT depend on v1 flow

Command mapping:

```text
4001 → auth
4011 → create account
4012 → balance
4021 → deposit/withdraw
4031 → launch
```

```