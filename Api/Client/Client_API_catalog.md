Here is your translated `.md` content (references removed, no additions or omissions):

---

# VinPlayPortal API Documentation

This document is rewritten from the existing source code in the `VinPlayPortal` repo.

Objectives of this document:

* clearly describe which endpoints receive which inputs
* describe expected responses
* list error groups and error codes confirmed from source
* specify which parts are directly confirmed in code and which are still legacy behavior

Important notes:

* V2 API has a clearer contract with a unified response envelope.
* Legacy API is inconsistent. Some endpoints return JSON objects, some return plain strings, some return `"MISSING PARAMETTER"`.
* This document prioritizes accuracy based on source, without guessing fields not found in code.

## 1. Base URL and routing

### Legacy API

* Method: `GET` or `POST`
* Common endpoint: `/api`
* Command selected via query param `c`
* Example:

```http
GET /api?c=3&un=testuser&pw=123456
POST /api?c=124
```

### V2 API

* Method: `POST`
* Endpoint: `/api/v2/{commandId}`
* Request body: JSON
* `GET /api/v2/*` is not supported

### Special endpoint

* `POST /api/login-token`

  * separate servlet
  * internally maps to command `3006`

## 2. General conventions

### 2.1 Legacy request

* Uses short query params:

  * `un`: username
  * `pw`: password
  * `nn`: nickname
  * `at`: access token
  * `s`: social provider
  * `otp`: OTP code
  * `type`: OTP type
  * `pf`: platform
  * `cp`: captcha text
  * `cid`: captcha id

### 2.2 Legacy response

* No unified envelope.
* Confirmed response types:

  * JSON like `LoginResponse` / `BaseResponseModel`: includes `success`, `errorCode`, possibly `sessionKey`, `accessToken`, `nickname`, `secret`, `otp`
  * standard JSON object (e.g. captcha)
  * raw string:

    * timestamp millis
    * `"MISSING PARAMETTER"`
    * `"PLATFORM NOT SUPPORT"`
    * raw config content

### 2.3 V2 request

* JSON body
* `SecurityFilter` reads body once and caches in `requestBody`
* If JWT required, `operatorCode` is taken from token

### 2.4 V2 response envelope

```json
{
  "success": true,
  "errorCode": "0",
  "errorMessage": "Success",
  "timestamp": 1710000000000,
  "data": {},
  "metadata": {}
}
```

Meaning:

* `success`: result
* `errorCode`: string code
* `errorMessage`: short description
* `timestamp`: epoch millis
* `data`: business data
* `metadata`: optional info

### 2.5 HTTP status for v2

From `SecurityFilter`:

* `1xxx`: HTTP `400`
* `2xxx`: HTTP `401`
* `2001`: HTTP `429`
* `5xxx`: HTTP `500`

Note:

* some processors return error envelope but still HTTP `200`

## 3. Auth and security (v2)

### Public endpoints

* `POST /api/v2/4001`
* `POST /api/v2/4002`
* `POST /api/v2/5001`
* `POST /api/v2/5002`

### Admin endpoints

* `POST /api/v2/5011`
* `POST /api/v2/5012`
* `POST /api/v2/5013`

If `admin.token` exists:

* require header `X-Admin-Token`

Otherwise:

* allow access for backward compatibility

### Bearer token endpoints

All others.

Headers:

```http
Authorization: Bearer <jwt>
X-Request-ID: <optional-idempotency-key>
```

Behavior:

* decode JWT → `operatorCode`
* fetch `secretKey`
* verify JWT
* `X-Request-ID` may return cached response

## 4. V2 Error Codes

| Code   | Meaning                                   |
| ------ | ----------------------------------------- |
| `0`    | Success                                   |
| `0001` | Success with warning                      |
| `1000` | General validation error                  |
| `1001` | Invalid operator code                     |
| `1002` | Invalid parameters                        |
| `1003` | Invalid signature                         |
| `1004` | Invalid username format                   |
| `1005` | Invalid password format                   |
| `1006` | Username already exists                   |
| `1007` | Data update error                         |
| `1008` | Account not found                         |
| `1009` | Unspecified error                         |
| `1010` | Invalid IP                                |
| `1011` | Account creation failed                   |
| `1012` | Insufficient balance                      |
| `1013` | Invalid token format                      |
| `1014` | User not found                            |
| `1015` | Invalid old password                      |
| `1016` | Duplicate transaction ID                  |
| `1017` | Invalid timestamp                         |
| `1018` | Invalid nonce                             |
| `1019` | Invalid currency                          |
| `1020` | Invalid amount                            |
| `1021` | Invalid transaction type                  |
| `1022` | Request too large                         |
| `1023` | Invalid JSON                              |
| `2000` | Authentication required                   |
| `2001` | Rate limit                                |
| `2002` | Token expired                             |
| `2003` | Token revoked                             |
| `2004` | Invalid refresh token                     |
| `2005` | Permission denied                         |
| `2006` | Account suspended                         |
| `2007` | Account banned                            |
| `2008` | Operator suspended                        |
| `2009` | Invalid API key                           |
| `2010` | Secret key mismatch                       |
| `3000` | Business error                            |
| `3001` | Transfer not allowed or account not found |
| `3002` | Daily limit                               |
| `3003` | Monthly limit                             |
| `3004` | Duplicate transaction                     |
| `3005` | Max transfer exceeded                     |
| `3006` | Account locked                            |
| `3007` | Session active                            |
| `3008` | Session not found                         |
| `3009` | Bet not allowed                           |
| `3010` | Currency mismatch                         |
| `3011` | Transaction not found                     |
| `4000` | External service error                    |
| `4001` | DB error                                  |
| `4002` | Cache error                               |
| `4003` | MQ error                                  |
| `4004` | Payment gateway error                     |
| `5000` | Internal error                            |
| `5001` | Service unavailable                       |
| `5002` | Timeout                                   |
| `5003` | Config error                              |
| `5004` | Maintenance                               |

Note:

* `3001` duplicated meaning in source.

## 5. V2 API Details

### 5.1 `4001` - Get access token

* Public endpoint

Request:

```json
{
  "operatorCode": "OP001",
  "apiKey": "your-api-key",
  "timestamp": 1710000000000,
  "signature": "generated-signature"
}
```

Response:

```json
{
  "accessToken": "jwt-access-token",
  "refreshToken": "jwt-refresh-token",
  "tokenType": "Bearer",
  "expiresIn": 3600,
  "scope": "default"
}
```

### 5.2 `4002` - Refresh token

Request:

```json
{
  "refreshToken": "jwt-refresh-token"
}
```

Response:
same structure as `4001`.

### 5.3 `4011` - Create account

Request:

```json
{
  "operatorCode": "OP001",
  "username": "player_001",
  "currency": "VND"
}
```

Response:

```json
{
  "username": "player_001",
  "accountId": "12345",
  "currency": "VND",
  "balance": 0,
  "createdAt": 1710000000000,
  "status": "ACTIVE"
}
```

### 5.4 `4012` - Get balance

Request:

```json
{
  "operatorCode": "OP001",
  "username": "player_001"
}
```

Response:

```json
{
  "username": "player_001",
  "accountId": "12345",
  "currency": "VND",
  "balance": 100000,
  "availableBalance": 100000,
  "lockedBalance": 0,
  "lastUpdated": 1710000000000
}
```

### 5.5 `4021` - Deposit/Withdraw

Request:

```json
{
  "operatorCode": "OP001",
  "username": "player_001",
  "transactionId": "TXN-001",
  "type": "DEPOSIT",
  "amount": 50000,
  "currency": "VND",
  "description": "Top up"
}
```

Response:

```json
{
  "transactionId": "TXN-001",
  "username": "player_001",
  "type": "DEPOSIT",
  "amount": 50000,
  "currency": "VND",
  "balanceBefore": 100000,
  "balanceAfter": 150000,
  "status": "SUCCESS",
  "processedAt": 1710000000000,
  "note": null
}
```

### 5.6 `4031` - Get launch URL

Request:

```json
{
  "operatorCode": "OP001",
  "username": "player_001",
  "gameId": "SLOT01",
  "platform": "web",
  "language": "vi",
  "returnUrl": "https://partner.example.com/back"
}
```

Response:

```json
{
  "launchUrl": "...",
  "sessionToken": "...",
  "expiresIn": 3600,
  "expiresAt": 1710003600000,
  "gameInfo": {}
}
```

### 5.7 `4041` - Betting history

Request:

```json
{
  "ticket": 123456789,
  "limit": 20
}
```

Response: MongoDB documents list.

### 5.8 `4042` - Payment transaction

Request:

```json
{
  "agentTransactionId": "TXN-001"
}
```

Response: transaction list.

### 5.9 `5001` - Health

### 5.10 `5002` - Pool monitoring

### 5.11 `5012` - Create partner

### 5.12 `5013` - Init DB

### 5.13 `5099` - DB health bypass

## 6. Legacy API Details

### `c=2` Login with token

### `c=3` Login

### `c=4` Login with OTP

### `c=5` Set nickname

### `c=6` App config

### `c=9` Server time

### `c=10` Admin config

### `c=11` VinPlus config

### `c=16` OTP eSMS

### `c=124` Captcha

### `c=127` Forgot password

### `c=128` Confirm OTP reset

### `c=133` Forgot password email

### `c=2000` Set 2FA

### `c=2003` Set PIN

### `c=2004` Get OTP from PIN

### `c=2005` Remove PIN

### `c=2006` Apple login

## 7. Special Legacy Behavior

* Commands `3010`, `3019` return `"Successful"` when `err_code=0`

## 8. Document Limitations

Confirmed:

* routing
* auth/security
* v2 envelope
* DTO
* most auth/profile/OTP params

Not fully confirmed:

* all legacy responses
* full error meanings
* all mini-game/payment/mailbox APIs

---