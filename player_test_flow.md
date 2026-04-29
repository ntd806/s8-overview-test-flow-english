# Hướng dẫn chạy `player_test_flow-v1.sh`

File này mô tả đúng luồng hiện tại của script [player_test_flow-v1.sh](/Users/anthonynguyen/Downloads/ProjectsS8/winall_svn/s8-backend/player_test_flow-v1.sh).

## 1. Mục tiêu

Script dùng để test flow v1 của Portal:

```text
Lấy captcha
Register user mới
Login
Nếu chưa có nickname thì set nickname
Lấy sessionKey
Lấy config game
```

Kết quả cuối cùng cần lấy được:

```text
USERNAME
PASSWORD
NICKNAME
SESSIONKEY
```

Sau đó dùng `NICKNAME + SESSIONKEY` để login vào game socket.

## 2. Điều kiện trước khi chạy

Cần bảo đảm Portal v1 đang chạy ở:

```text
http://127.0.0.1:8081/api
```

Test nhanh:

```bash
curl -s 'http://127.0.0.1:8081/api?c=124'
```

Nếu trả về JSON có `id` và `img` thì Portal đang chạy đúng.

## 3. Cấp quyền và chạy script

```bash
chmod +x /Users/anthonynguyen/Downloads/ProjectsS8/winall_svn/s8-backend/player_test_flow-v1.sh
cd /Users/anthonynguyen/Downloads/ProjectsS8/winall_svn/s8-backend
./player_test_flow-v1.sh
```

## 4. Script đang tự sinh dữ liệu như thế nào

Script hiện tại không cần sửa tay đầu file trong hầu hết trường hợp.

Nó tự sinh:

```text
USERNAME = test + 7 số cuối của timestamp
PASSWORD = 123456
NICKNAME = play_ + 7 số cuối của timestamp
```

Ví dụ:

```text
USERNAME = test4812184
PASSWORD = 123456
NICKNAME = play_4812184
```

Giới hạn mà script đang tuân theo:

```text
USERNAME chỉ gồm chữ và số, dài 6-16 ký tự
NICKNAME gồm chữ, số, dấu _, dài 6-16 ký tự
```

## 5. Luồng chạy thực tế

### Bước 1: Lấy captcha

Script gọi:

```bash
curl -s 'http://127.0.0.1:8081/api?c=124'
```

Sau đó:

```text
Lưu ảnh vào captcha.png
Mở ảnh captcha.png
Yêu cầu nhập 3 ký tự captcha
```

### Bước 2: Register

Script gọi:

```bash
curl -s "http://127.0.0.1:8081/api?c=1&un=$USERNAME&pw=$PASSWORD&cp=$CAPTCHA&cid=$CID"
```

Kết quả thường gặp:

```text
errorCode = 0     -> register thành công
errorCode = 1006  -> user đã tồn tại, script vẫn cho đi tiếp login
errorCode = 115   -> captcha sai
errorCode = 101   -> username không hợp lệ
```

### Bước 3: Login

Script gọi:

```bash
curl -s "http://127.0.0.1:8081/api?c=3&un=$USERNAME&pw=$PASSWORD"
```

Các nhánh script đang xử lý:

```text
success = true + có sessionKey -> login thành công
errorCode = 2001               -> user chưa có nickname, chuyển sang bước set nickname
errorCode = 1001               -> script thử login lại bằng mật khẩu MD5
```

Nếu login plain password bị `1001`, script sẽ tự thử:

```bash
pw=MD5(123456)
```

Nếu login bằng MD5 vẫn lỗi, script sẽ dừng.

### Bước 4: Set nickname nếu chưa có nickname

Khi login trả `2001`, script gọi:

```bash
curl -s "http://127.0.0.1:8081/api?c=5&un=$USERNAME&pw=$LOGIN_PASSWORD&nn=$NICKNAME"
```

Các nhánh script đang xử lý:

```text
success = true + có sessionKey -> thành công
errorCode = 106                -> nickname không hợp lệ, script tự rút ngắn nickname và thử lại
errorCode = 1013               -> nickname đã tồn tại, script login lại để lấy sessionKey
```

Nickname fallback khi gặp `106`:

```text
p + 7 số cuối của timestamp
```

Ví dụ:

```text
p4812184
```

### Bước 5: Lấy config game

Script gọi:

```bash
curl -s 'http://127.0.0.1:8081/api?c=6&v=1&pf=web&did=test&vnt='
```

Mục đích:

```text
Xem game đang public host/port nào
```

### Bước 6: In kết quả cuối

Script in ra:

```text
USERNAME
PASSWORD
NICKNAME
SESSIONKEY
```

## 6. Cách đọc kết quả đúng

### Trường hợp chuẩn

```text
STEP 2 register -> errorCode 0
STEP 3 login    -> errorCode 2001
STEP 4 set nick -> errorCode 0
FINAL RESULT    -> có SESSIONKEY
```

Hoặc:

```text
STEP 2 register -> errorCode 1006
STEP 3 login    -> success true
FINAL RESULT    -> có SESSIONKEY
```

## 7. Các lỗi hay gặp

### `115`

Captcha sai.

Cách xử lý:

```text
Chạy lại script
Nhập đúng 3 ký tự captcha mới
```

### `101`

Username không hợp lệ.

Hiện tại script đã tự sinh username đúng chuẩn. Nếu vẫn gặp lỗi này thì thường là do bạn đã override biến môi trường `USERNAME` bằng giá trị không hợp lệ.

Test lại bằng cách không truyền `USERNAME` custom.

### `2001`

User chưa có nickname.

Đây là trạng thái bình thường sau khi vừa register thành công.

Script sẽ tự chuyển sang bước set nickname.

### `106`

Nickname không hợp lệ.

Script hiện tại đã có nhánh retry nickname ngắn hơn.

Nếu vẫn gặp lại, thường là do bạn truyền `NICKNAME` custom quá dài hoặc sai pattern.

### `1013`

Nickname đã tồn tại.

Script sẽ thử login lại để lấy `sessionKey`.

### `1001`

Login lỗi.

Script sẽ thử lại bằng password MD5.

Nếu vẫn fail thì thường là local procedure hoặc dữ liệu local đang lệch.

### `1005`

User không tồn tại hoặc Portal đang đọc sai trạng thái dữ liệu hiện tại.

Với flow local mới, lỗi này không nên xuất hiện ở user vừa register thành công.

## 8. Cách dùng kết quả để vào game

Sau khi script chạy xong, lấy:

```text
NICKNAME
SESSIONKEY
```

Ví dụ game Bacay:

```text
ws://127.0.0.1:21044
```

Dùng:

```text
nickname = giá trị NICKNAME ở cuối script
sessionKey = giá trị SESSIONKEY ở cuối script
```

## 9. Ghi chú quan trọng

Script này đang bám theo Portal v1 cũ:

```text
c=124 -> captcha
c=1   -> register
c=3   -> login
c=5   -> set nickname
c=6   -> get config
```

File này chỉ mô tả đúng luồng của `player_test_flow-v1.sh`, không mô tả flow v2.
