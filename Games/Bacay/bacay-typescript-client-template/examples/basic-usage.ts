import { BacayFrontendClient } from "../src";

const client = new BacayFrontendClient({
  wsUrl: "ws://127.0.0.1:21044/websocket",
  nickname: "test_user",
  sessionKey: "replace_with_real_session_key",

  joinConfig: {
    mode: "by-bet",
    moneyType: 0,
    maxUserPerRoom: 8,
    moneyBet: 1000,
    rule: 0,
  },

  reconnect: {
    enabled: true,
    maxAttempts: 5,
    baseDelayMs: 1000,
    maxDelayMs: 10000,
  },

  handlers: {
    onOpen() {
      console.log("[open] socket connected");
    },

    onClose(event) {
      console.log("[close]", event.code, event.reason);
    },

    onError(error) {
      console.error("[error]", error.code, error.message);
    },

    onReconnectStart(attempt, delayMs) {
      console.log(`[reconnect] attempt=${attempt}, delay=${delayMs}ms`);
    },

    onReconnectSuccess() {
      console.log("[reconnect] success");
    },

    onReconnectFailed(error) {
      console.error("[reconnect] failed", error.message);
    },

    onRawMessage(packet) {
      console.log(`[recv] cmd=${packet.cmd}, hex=${packet.rawHex}`);
    },

    onLoginSuccess() {
      console.log("[login] success");
    },

    onLoginError(error) {
      console.error("[login] failed", error.message);
    },

    onJoinSuccess() {
      console.log("[join] received 3118 JOIN_ROOM_SUCCESS");
    },

    onJoinError(error, detail) {
      console.error("[join] failed", error.message, detail);
    },

    onReconnectInfo(packet) {
      console.log("[sync] received 3110 THONG_TIN_BAN_CHOI", packet);
    },

    onGameMessage(packet) {
      console.log("[game]", packet.cmd);
    },
  },
});

client.connect();
