# Hướng dẫn dùng `NICKNAME` + `SESSIONKEY` với `s8-test-socket`

File này hướng dẫn cách lấy `NICKNAME`, `SESSIONKEY` từ Portal v1 rồi dùng chúng để test kết nối game socket trên dự án:

[`/Users/anthonynguyen/Downloads/bacay-express-tester/s8-test-socket`](/Users/anthonynguyen/Downloads/bacay-express-tester/s8-test-socket)

## 1. Mục tiêu

Dùng `s8-test-socket` để test trực quan các bước:

```text
Mở WebSocket tới game
Gửi packet login bằng nickname + sessionKey
Xác nhận login thành công
Gửi thêm join room / action hex trên cùng socket
```

## 2. Lấy `NICKNAME` và `SESSIONKEY`

Trước hết chạy:

```bash
cd /Users/anthonynguyen/Downloads/ProjectsS8/winall_svn/s8-backend
./player_test_flow-v1.sh
```

Kết quả cuối cần lấy:

```text
USERNAME   = ...
PASSWORD   = 123456
NICKNAME   = ...
SESSIONKEY = ...
```

Ví dụ:

```text
NICKNAME   = play_4812184
SESSIONKEY = eyJuaWNrbmFtZSI6InBsYXlfNDgxMjE4NCIs...
```

Sau đó dùng chính `NICKNAME` và `SESSIONKEY` này để login game socket.

## 3. Chạy `s8-test-socket`

Vào thư mục tool:

```bash
git clone git@github.com:ntd806/s8-test-socket.git \
&& cd s8-test-socket \
&& docker compose up -d --build
```

Mở web:

```text
http://127.0.0.1:3000/
```

## 4. Luồng test đúng trong web UI

Web tester hiện dùng WebSocket binary thật qua path:

```text
/websocket
```

Luồng thao tác chuẩn:

1. Chọn game.
2. Điền `host`.
3. Điền `port`.
4. Giữ `WS Path=/websocket`.
5. Bấm `Kết nối`.
6. Paste `SESSIONKEY`.
7. Nếu ô `Nickname` đang trống, app sẽ tự điền nickname từ payload trong `SESSIONKEY`.
8. Có thể bấm `Tạo Login Hex`, hoặc để app tự sinh sau khi connect.
9. Bấm `Login`.
10. Nếu cần test tiếp, paste `Join Room Hex` hoặc `Action Hex` rồi gửi tiếp trên cùng socket.

## 5. Dùng `SESSIONKEY` như thế nào

Trong UI của `s8-test-socket`:

```text
Ô Session Key -> dán SESSIONKEY từ player_test_flow-v1.sh
Ô Nickname    -> dán NICKNAME nếu muốn, hoặc để trống để app tự fill từ SESSIONKEY
```

Tool hiện có logic:

```text
Nếu nickname đang trống và sessionKey decode được payload.nickname
thì app tự điền nickname
```

Vì vậy cách an toàn nhất là:

```text
Dán cả SESSIONKEY và NICKNAME
```

## 6. Login Hex tool tự sinh là gì

Web tester đang tự tạo frame login BitZero WebSocket theo dạng:

```text
00 00 00
01
00 01
00 01
<nickname string>
<sessionKey string>
```

Ý nghĩa:

```text
00 00 00 -> prefix WS mà BitZero WebSocketCodec bỏ qua
01       -> controller id
00 01    -> request id login
00 01    -> dataCmd id login
nickname -> string có prefix length 2 byte
sessionKey -> string có prefix length 2 byte
```

Thông thường bạn không cần tự build tay vì app đã tự sinh `Login Hex`.

## 7. Port game local để test WS

Các port WS local hiện tại:

```text
Bacay       -> 21044
Baicao      -> 21144
BanCa       -> 21244
Binh        -> 21344
Caro        -> 21444
Cotuong     -> 22544
Coup        -> 21544
Lieng       -> 21644
Poker       -> 21744
PokerTour   -> 21844
Sam         -> 21944
SlotMachine -> 22044
Tienlen     -> 22144
Xizach      -> 22244
minigame    -> 22344
xocdia      -> 22444
```

Host local thường là:

```text
127.0.0.1
```

Ví dụ test Bacay:

```text
Host    = 127.0.0.1
Port    = 21044
WS Path = /websocket
URL     = ws://127.0.0.1:21044/websocket
```

## 8. Ví dụ test nhanh với Bacay

### Bước 1

Lấy `NICKNAME` và `SESSIONKEY` từ:

```bash
./player_test_flow-v1.sh
```

### Bước 2

Mở:

```text
http://127.0.0.1:3000/
```

### Bước 3

Chọn:

```text
Game    = Bacay
Host    = 127.0.0.1
Port    = 21044
Path    = /websocket
```

### Bước 4

Bấm:

```text
Kết nối
```

Kết quả mong đợi:

```text
WebSocket opened
hoặc summary báo đã kết nối tới ws://127.0.0.1:21044/websocket
```

### Bước 5

Dán:

```text
Session Key = <SESSIONKEY>
Nickname    = <NICKNAME>
```

### Bước 6

Bấm:

```text
Tạo Login Hex
Login
```

Kết quả mong đợi:

```text
Có response binary trả về
Không timeout
Không bị socket close ngay sau login
```

## 9. Sau login thì test gì tiếp

Sau khi login socket thành công, bạn có thể test tiếp:

```text
Join Room Hex
Action Hex
Reconnect flow
Leave room
```

Các packet này phải gửi trên cùng socket đã login.

## 10. Dấu hiệu pass cơ bản

Một game được xem là pass mức tối thiểu khi:

```text
Connect WS thành công
Login packet gửi đi thành công
Có response từ server
Socket không bị đóng ngay
Có thể gửi thêm packet join room hoặc action
```

## 11. Lỗi hay gặp

### Không connect được

Kiểm tra:

```text
Game container đã chạy chưa
Port WS đúng chưa
Host đúng chưa
WS Path có phải /websocket không
```

### Connect được nhưng login fail

Kiểm tra:

```text
SESSIONKEY có phải mới lấy từ Portal không
NICKNAME có đúng user của SESSIONKEY không
Game đó có đúng WS port không
Login Hex có đúng controller/request/dataCmd không
```

### App báo thiếu cấu hình WS

Ý nghĩa:

```text
Game đó chưa có <GAME>_WS_PORT hoặc <GAME>_WSS_PORT trong .env của s8-test-socket
```

Browser tester không dùng `GAME_PORT` TCP để mở WebSocket.

### Timeout sau khi gửi login

Kiểm tra:

```text
Packet login đã đúng format chưa
SESSIONKEY còn hiệu lực không
Socket server có đang nhận đúng path /websocket không
```

## 12. Ghi chú quan trọng

`s8-test-socket` đang test theo hướng WebSocket binary thật, không phải REST API.

Vì vậy:

```text
Portal dùng để lấy session
Socket game dùng để connect/login/join/action
```

`SESSIONKEY` lấy từ Portal v1 hiện là dữ liệu quan trọng nhất để vào game socket ở tool này.
