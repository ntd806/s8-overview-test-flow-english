# Test client config for scripts/test-bacay-flow.js
# Use the deployed/original ports when testing the original artifact:
# BACAY_WS_URL=ws://127.0.0.1:1244/websocket
# Use the Docker/local ports when testing this repo locally:
BACAY_WS_URL=ws://43.207.3.134:21044/websocket

# Values returned by your HTTP/API login step
BACAY_NICKNAME=play_7698014
BACAY_SESSION_KEY=eyJuaWNrbmFtZSI6InBsYXlfNzY0OTYxNyIsImF2YXRhciI6IjAiLCJ2aW5Ub3RhbCI6MCwieHVUb3RhbCI6MCwidmlwcG9pbnQiOjAsInZpcHBvaW50U2F2ZSI6MCwiY3JlYXRlVGltZSI6IjAxLTA1LTIwMjYiLCJpcEFkZHJlc3MiOiIxNzIuMTguMC4xIiwiY2VydGlmaWNhdGUiOmZhbHNlLCJsdWNreVJvdGF0ZSI6MCwiZGFpTHkiOjAsIm1vYmlsZVNlY3VyZSI6MCwiYXBwU2VjdXJlIjowLCJiaXJ0aGRheSI6IiIsImlkIjowfQ==

# Raw BitZero core packets in hex
# You can generate these from this .env with:
# node scripts/build-bitzero-frames.js
BACAY_LOGIN_PACKET_HEX=
BACAY_JOIN_PACKET_HEX=

# Join packet generator config
# by-bet    -> action 3001, body: moneyType + maxUserPerRoom + moneyBet + rule
# by-room-id -> action 3015, body: roomId + password
BACAY_JOIN_MODE=by-bet
BACAY_MONEY_TYPE=0
BACAY_MAX_USER_PER_ROOM=8
BACAY_MONEY_BET=1000
BACAY_RULE=0
BACAY_ROOM_ID=1
BACAY_ROOM_PASSWORD=
BACAY_ROOM_LIST_FROM=0
BACAY_ROOM_LIST_TO=20

# Test client behavior
BACAY_AUTO_LOGIN=true
BACAY_AUTO_JOIN=true
BACAY_JOIN_DELAY_MS=1500
BACAY_RUN_MS=15000
BACAY_POST_JOIN_COMMAND_ID=3111
BACAY_POST_JOIN_COMMAND_DELAY_MS=2500
BACAY_POST_JOIN_COMMAND_BODY_HEX=
BACAY_POST_JOIN_COMMAND_PACKET_HEX=
