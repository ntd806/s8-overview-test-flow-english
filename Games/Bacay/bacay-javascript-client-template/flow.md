# Bacay Integration Flow

1. Login API → get nickname + sessionKey
2. Connect WebSocket
3. Send LOGIN (cmd=1)
4. If success → joinRoom()
5. Wait for 3118 (JOIN_ROOM_SUCCESS)
6. Start game flow

Game Commands:
- DAT_CUOC (3109)
- MO_BAI (3101)
