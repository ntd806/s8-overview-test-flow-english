# Hướng dẫn chạy `test_v2_full_flow.sh`

File này mô tả đúng luồng hiện tại của script [test_v2_full_flow.sh](/Users/anthonynguyen/Downloads/ProjectsS8/winall_svn/s8-backend/test_v2_full_flow.sh).

## 1. Mục tiêu

Script dùng để test full flow API v2 của Portal:

```text
Lấy access token
Tạo account
Kiểm tra balance
Deposit
Launch game
Withdraw
Kiểm tra balance cuối
```

Kết quả cuối cùng mong muốn:

```text
FULL FLOW PASSED
USER = ...
FINAL_BALANCE = DEPOSIT_AMOUNT - WITHDRAW_AMOUNT
```

## 2. Điều kiện trước khi chạy

Cần bảo đảm Portal v2 đang chạy ở:

```text
http://127.0.0.1:8081
```

Và endpoint auth v2 hoạt động:

```text
POST /api/v2/4001
```

## 3. Chạy script

```bash
chmod +x /Users/anthonynguyen/Downloads/ProjectsS8/winall_svn/s8-backend/test_v2_full_flow.sh
cd /Users/anthonynguyen/Downloads/ProjectsS8/winall_svn/s8-backend
./test_v2_full_flow.sh
```

## 4. Các biến cấu hình script đang dùng

Script hỗ trợ override bằng biến môi trường.

Giá trị mặc định hiện tại:

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

User test được sinh tự động:

```text
USER = curlv2_<timestamp>
TXN = txn_<USER>
WITHDRAW_TXN = txn_<USER>_w
```

Ví dụ chạy custom:

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

## 5. Luồng chạy thực tế

### Bước 1: Get access token

Script gọi:

```text
POST /api/v2/4001
```

Body gửi lên:

```json
{
  "operatorCode": "default",
  "apiKey": "default_secret_key",
  "timestamp": 1777481053512,
  "signature": "..."
}
```

`signature` được tạo bằng:

```text
HMAC-SHA256(secret, operatorCode + apiKey + timestamp)
```

Script sẽ dừng nếu:

```text
success != true
hoặc không extract được accessToken
```

Kết quả mong đợi:

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

### Bước 2: Create account

Script gọi:

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

Kết quả mong đợi:

```text
success = true
errorCode = 0
```

### Bước 3: Check balance

Script gọi:

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

Kết quả mong đợi ban đầu thường là:

```text
balance = 0
```

### Bước 4: Deposit

Script gọi:

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

Kết quả mong đợi:

```text
success = true
```

### Bước 5: Launch game

Script gọi:

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

Kết quả mong đợi:

```json
{
  "success": true,
  "data": {
    "launchUrl": "...",
    "sessionToken": "..."
  }
}
```

### Bước 6: Withdraw

Script gọi:

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

Kết quả mong đợi:

```text
success = true
```

### Bước 7: Final balance

Script gọi lại:

```text
POST /api/v2/4012
Authorization: Bearer <accessToken>
```

Sau đó script tự so:

```text
EXPECTED_BALANCE = DEPOSIT_AMOUNT - WITHDRAW_AMOUNT
ACTUAL_BALANCE   = balance từ response cuối
```

Nếu lệch, script dừng với:

```text
Balance mismatch
```

## 6. Kết quả cuối đúng

Khi pass toàn bộ, script in:

```text
✅ FULL FLOW PASSED
USER: curlv2_<timestamp>
FINAL_BALANCE: 7000
```

Với mặc định hiện tại:

```text
10000 - 3000 = 7000
```

## 7. Các lỗi hay gặp

### `FAILED at step: Get access token`

Nguyên nhân thường gặp:

```text
Sai OP
Sai API_KEY
Sai SECRET
Portal v2 chưa chạy
Signature HMAC không đúng
```

Kiểm tra:

```text
POST /api/v2/4001 có trả success=true không
```

### `Cannot extract accessToken`

Nguyên nhân:

```text
Response auth không có data.accessToken
JSON trả về khác format script đang parse
```

### `FAILED at step: Create account`

Nguyên nhân thường gặp:

```text
JWT Bearer token không hợp lệ
operatorCode không hợp lệ
DB tạo account lỗi
```

### `FAILED at step: Check balance`

Nguyên nhân thường gặp:

```text
User chưa tạo đúng
Bearer token không hợp lệ
Flow multi-tenant hoặc cache lỗi
```

### `FAILED at step: Deposit`

Nguyên nhân thường gặp:

```text
transactionId bị trùng
user không tồn tại
money service lỗi
```

### `FAILED at step: Launch game`

Nguyên nhân thường gặp:

```text
gameId không hợp lệ
user không tồn tại
token không hợp lệ
```

### `FAILED at step: Withdraw`

Nguyên nhân thường gặp:

```text
Không đủ balance
transactionId trùng
user không tồn tại
```

### `Balance mismatch`

Nghĩa là:

```text
API deposit/withdraw trả success
nhưng số dư cuối không khớp phép tính mong đợi
```

Cần kiểm tra:

```text
Response của bước deposit
Response của bước withdraw
Response balance cuối
```

## 8. Ghi chú quan trọng

Script này:

```text
chỉ test API v2
không dùng captcha
không dùng register/login v1
không cần set nickname kiểu flow v1
```

Thứ tự commandId v2 trong script:

```text
4001 -> auth token
4011 -> create account
4012 -> get balance
4021 -> deposit / withdraw
4031 -> launch game
```

File này chỉ mô tả đúng luồng hiện tại của `test_v2_full_flow.sh`.
