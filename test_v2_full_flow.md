# How to Run `test_v2_full_flow.sh`

This file describes the current flow of the script [test_v2_full_flow.sh](/Users/anthonynguyen/Downloads/ProjectsS8/winall_svn/s8-backend/test_v2_full_flow.sh).

## 1. Goal

This script is used to test the full Portal API v2 flow:

```text
Get access token
Create account
Check balance
Deposit
Launch game
Withdraw
Check final balance
```

Expected final result:

```text
FULL FLOW PASSED
USER = ...
FINAL_BALANCE = DEPOSIT_AMOUNT - WITHDRAW_AMOUNT
```

## 2. Requirements Before Running

Make sure Portal v2 is running at:

```text
http://127.0.0.1:8081
```

And make sure the v2 auth endpoint works:

```text
POST /api/v2/4001
```

## 3. Run the Script

```bash
chmod +x /Users/anthonynguyen/Downloads/ProjectsS8/winall_svn/s8-backend/test_v2_full_flow.sh
cd /Users/anthonynguyen/Downloads/ProjectsS8/winall_svn/s8-backend
./test_v2_full_flow.sh
```

## 4. Script Configuration Variables

The script supports overrides through environment variables.

Current default values:

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

The test user is generated automatically:

```text
USER = curlv2_<timestamp>
TXN = txn_<USER>
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

## 5. Actual Runtime Flow

### Step 1: Get access token

The script calls:

```text
POST /api/v2/4001
```

Request body:

```json
{
  "operatorCode": "default",
  "apiKey": "default_secret_key",
  "timestamp": 1777481053512,
  "signature": "..."
}
```

`signature` is generated with:

```text
HMAC-SHA256(secret, operatorCode + apiKey + timestamp)
```

The script stops if:

```text
success != true
or accessToken cannot be extracted
```

Expected response:

```json
{
  "success": true,
  "errorCode": "0",
  "data": {
    "accessToken": "...",
    "refreshToken": "..."
  }
}
```

### Step 2: Create account

The script calls:

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

Expected result:

```text
success = true
errorCode = 0
```

### Step 3: Check balance

The script calls:

```text
POST /api/v2/4012
Authorization: Bearer <accessToken>
```

Body:

```json
{
  "operatorCode": "default",
  "username": "curlv2_<timestamp>"
}
```

The initial expected result is usually:

```text
balance = 0
```

### Step 4: Deposit

The script calls:

```text
POST /api/v2/4021
Authorization: Bearer <accessToken>
```

Body:

```json
{
  "operatorCode": "default",
  "username": "curlv2_<timestamp>",
  "transactionId": "txn_<USER>",
  "type": "DEPOSIT",
  "amount": 10000,
  "currency": "VND"
}
```

Expected result:

```text
success = true
```

### Step 5: Launch game

The script calls:

```text
POST /api/v2/4031
Authorization: Bearer <accessToken>
```

Body:

```json
{
  "operatorCode": "default",
  "username": "curlv2_<timestamp>",
  "gameId": "bacay",
  "platform": "WEB"
}
```

Expected response:

```json
{
  "success": true,
  "data": {
    "launchUrl": "...",
    "sessionToken": "..."
  }
}
```

### Step 6: Withdraw

The script calls:

```text
POST /api/v2/4021
Authorization: Bearer <accessToken>
```

Body:

```json
{
  "operatorCode": "default",
  "username": "curlv2_<timestamp>",
  "transactionId": "txn_<USER>_w",
  "type": "WITHDRAW",
  "amount": 3000,
  "currency": "VND"
}
```

Expected result:

```text
success = true
```

### Step 7: Final balance

The script calls again:

```text
POST /api/v2/4012
Authorization: Bearer <accessToken>
```

Then it compares:

```text
EXPECTED_BALANCE = DEPOSIT_AMOUNT - WITHDRAW_AMOUNT
ACTUAL_BALANCE   = balance from the final response
```

If they do not match, the script stops with:

```text
Balance mismatch
```

## 6. Correct Final Result

When the whole flow passes, the script prints:

```text
✅ FULL FLOW PASSED
USER: curlv2_<timestamp>
FINAL_BALANCE: 7000
```

With the current defaults:

```text
10000 - 3000 = 7000
```

## 7. Common Errors

### `FAILED at step: Get access token`

Common causes:

```text
Wrong OP
Wrong API_KEY
Wrong SECRET
Portal v2 is not running
Invalid HMAC signature
```

Check:

```text
Does POST /api/v2/4001 return success=true?
```

### `Cannot extract accessToken`

Cause:

```text
The auth response has no data.accessToken
The returned JSON format is different from what the script parses
```

### `FAILED at step: Create account`

Common causes:

```text
Invalid JWT Bearer token
Invalid operatorCode
Database error while creating the account
```

### `FAILED at step: Check balance`

Common causes:

```text
The user was not created correctly
Invalid Bearer token
Multi-tenant flow or cache issue
```

### `FAILED at step: Deposit`

Common causes:

```text
Duplicate transactionId
User does not exist
Money service error
```

### `FAILED at step: Launch game`

Common causes:

```text
Invalid gameId
User does not exist
Invalid token
```

### `FAILED at step: Withdraw`

Common causes:

```text
Insufficient balance
Duplicate transactionId
User does not exist
```

### `Balance mismatch`

This means:

```text
The deposit/withdraw API returned success
but the final balance does not match the expected calculation
```

Check:

```text
The response from the deposit step
The response from the withdraw step
The final balance response
```

## 8. Important Notes

This script:

```text
tests only API v2
does not use captcha
does not use v1 register/login
does not need the v1-style nickname setup flow
```

The v2 commandId order used in the script:

```text
4001 -> auth token
4011 -> create account
4012 -> get balance
4021 -> deposit / withdraw
4031 -> launch game
```

This file only describes the current flow of `test_v2_full_flow.sh`.
