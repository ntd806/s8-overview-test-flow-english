import { BacayFrontendClient } from "./client.js";

const client = new BacayFrontendClient({
  wsUrl: "ws://127.0.0.1:21044/websocket",
  nickname: "test",
  sessionKey: "xxx",

  onLoginSuccess() {
    console.log("Login success");
  },

  onJoinSuccess() {
    console.log("Joined room");
  },

  onGameMessage(packet) {
    console.log("Game packet:", packet);
  },
});

client.connect();
