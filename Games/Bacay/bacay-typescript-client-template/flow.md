# Bacay Flow Reference

## 1. Login API

Frontend should call the HTTP/API login first.

Expected result:

```ts
{
  nickname: string;
  sessionKey: string;
}
```

## 2. WebSocket Connect

Use the returned `nickname` and `sessionKey` to create the WebSocket client.

## 3. Core Login

After socket open, the client sends:

```text
cmd = 1
body = nickname + sessionKey
```

## 4. Join Room

After login success, the client automatically joins room by:

- `JOIN_BY_BET` / `3001`, or
- `JOIN_BY_ROOM_ID` / `3015`

## 5. Wait for 3118

Only after receiving `3118 JOIN_ROOM_SUCCESS`, game commands are allowed.

## 6. Game Commands

| Command | Code |
|---|---:|
| MO_BAI | 3101 |
| BAT_DAU | 3102 |
| KET_THUC | 3103 |
| YEU_CAU_DANH_BIEN | 3104 |
| CHIA_BAI | 3105 |
| KE_CUA | 3106 |
| DAT_CUOC | 3109 |
| THONG_TIN_BAN_CHOI | 3110 |
| DANG_KY_THOAT_PHONG | 3111 |
| VAO_GA | 3112 |
| JOIN_ROOM_SUCCESS | 3118 |
| CMD_SEND_UPDATE_MATCH | 3123 |
