# Overview tài liệu test
File này là hướng dẫn tổng quan: nên đọc file nào trước và chạy theo thứ tự nào.

## 1. Mục tiêu

Thứ tự khuyến nghị để test toàn bộ hệ thống:

```text
API v1 cũ
Socket game
API v2
```

Lý do:

```text
API v1 cũ giúp tạo user, login và lấy sessionKey
Socket game cần nickname + sessionKey từ API v1
API v2 nên test sau khi Portal và game socket đã xác nhận chạy ổn
```

## 2. Thứ tự đọc tài liệu

### Bước 1

Đọc file:

[testv1.md]

Mục đích:

```text
Hiểu luồng Portal v1
Biết cách chạy player_test_flow-v1.sh
Biết cách lấy USERNAME, NICKNAME, SESSIONKEY
```

### Bước 2

Chạy file:

```bash
cd root/ && ./player_test_flow-v1.sh
```

Kết quả cần có:

```text
NICKNAME
SESSIONKEY
```

### Bước 3

Đọc file:

[test_s8_test_socket.md]

Mục đích:

```text
Biết cách dùng NICKNAME + SESSIONKEY
Biết cách mở s8-test-socket
Biết cách connect và login vào game socket
```

### Bước 4

Chạy tool:

```bash
git clone git@github.com:ntd806/s8-test-socket.git \
&& cd s8-test-socket \
&& docker compose up -d --build
```

Sau đó mở:

```text
http://127.0.0.1:3000/
```

### Bước 5

Đọc file:

[test_v2_full_flow.md]
Mục đích:

```text
Hiểu flow API v2
Biết cách chạy test_v2_full_flow.sh
Biết các bước auth token, create account, balance, deposit, launch, withdraw
```

### Bước 6

Chạy file:

```bash
cd root && ./test_v2_full_flow.sh
```

## 3. Thứ tự chạy khuyến nghị

```text
1. Chạy player_test_flow-v1.sh
2. Lấy NICKNAME + SESSIONKEY
3. Dùng s8-test-socket để test connect/login game
4. Chạy test_v2_full_flow.sh
```

## 4. Nếu chỉ muốn test nhanh

### Chỉ test API v1 cũ

Đọc:

[testv1.md]

Chạy:

```bash
./player_test_flow-v1.sh
```

### Chỉ test socket game

Đọc:

[test_s8_test_socket.md]

Điều kiện:

```text
Phải có NICKNAME + SESSIONKEY trước
```

### Chỉ test API v2

Đọc:

[test_v2_full_flow.md]

Chạy:

```bash
./test_v2_full_flow.sh
```

## 5. Kết luận ngắn

Muốn test đúng thứ tự, hãy đi như sau:

```text
testv1.md
-> player_test_flow-v1.sh
-> test_s8_test_socket.md
-> http://127.0.0.1:3000/ (s8-test-socket)
-> test_v2_full_flow.md
-> test_v2_full_flow.sh
```
