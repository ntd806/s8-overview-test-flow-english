export class BacayFrontendClient {
  constructor({ wsUrl, nickname, sessionKey, onLoginSuccess, onJoinSuccess, onGameMessage }) {
    this.wsUrl = wsUrl;
    this.nickname = nickname;
    this.sessionKey = sessionKey;
    this.handlers = { onLoginSuccess, onJoinSuccess, onGameMessage };
  }

  connect() {
    this.socket = new WebSocket(this.wsUrl);
    this.socket.binaryType = "arraybuffer";

    this.socket.onopen = () => {
      this.sendLogin();
    };

    this.socket.onmessage = (event) => {
      const packet = this.decode(event.data);
      this.handle(packet);
    };
  }

  sendLogin() {
    const body = new TextEncoder().encode(this.nickname + "|" + this.sessionKey);
    this.send(1, body);
  }

  joinRoom() {
    this.send(3001, new Uint8Array());
  }

  send(cmd, body) {
    const buffer = new Uint8Array([cmd, ...body]);
    this.socket.send(buffer);
  }

  decode(data) {
    return new Uint8Array(data);
  }

  handle(packet) {
    const cmd = packet[0];

    if (cmd === 1) {
      this.handlers.onLoginSuccess && this.handlers.onLoginSuccess();
      this.joinRoom();
    }

    if (cmd === 3118) {
      this.handlers.onJoinSuccess && this.handlers.onJoinSuccess();
    }

    if (cmd >= 3101) {
      this.handlers.onGameMessage && this.handlers.onGameMessage(packet);
    }
  }
}
