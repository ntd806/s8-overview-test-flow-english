/*
 * Bacay frontend integration example
 *
 * This file is meant for frontend developers as a reference implementation.
 * It shows the real flow used by the current Bacay source:
 *
 * HTTP/API login -> get nickname + sessionKey
 * -> connect WebSocket
 * -> send BitZero core login
 * -> wait login success
 * -> join room
 * -> wait 3118
 * -> start Bacay game flow
 *
 * This is not a production-ready SDK. It is a small, readable example.
 */

const BacayCmd = {
  LOGIN: 1,
  JOIN_BY_BET: 3001,
  ROOM_LIST: 3014,
  JOIN_BY_ROOM_ID: 3015,

  MO_BAI: 3101,
  BAT_DAU: 3102,
  KET_THUC: 3103,
  YEU_CAU_DANH_BIEN: 3104,
  CHIA_BAI: 3105,
  KE_CUA: 3106,
  TU_DONG_BAT_DAU: 3107,
  DONG_Y_DANH_BIEN: 3108,
  DAT_CUOC: 3109,
  THONG_TIN_BAN_CHOI: 3110,
  DANG_KY_THOAT_PHONG: 3111,
  VAO_GA: 3112,
  DOI_CHUONG: 3113,
  MOI_DAT_CUOC: 3114,
  CHEAT_CARDS: 3115,
  DANG_KY_CHOI_TIEP: 3116,
  UPDATE_OWNER_ROOM: 3117,
  JOIN_ROOM_SUCCESS: 3118,
  LEAVE_GAME: 3119,
  NOTIFY_KICK_FROM_ROOM: 3120,
  NEW_USER_JOIN: 3121,
  NOTIFY_USER_GET_JACKPOT: 3122,
  CMD_SEND_UPDATE_MATCH: 3123,
};

class BacayFrontendClient {
  constructor(options) {
    this.wsUrl = options.wsUrl;
    this.nickname = options.nickname;
    this.sessionKey = options.sessionKey;
    this.joinConfig = options.joinConfig || {
      mode: "by-bet",
      moneyType: 0,
      maxUserPerRoom: 8,
      moneyBet: 1000,
      rule: 0,
    };

    this.socket = null;
    this.state = {
      socket: "idle",
      login: "idle",
      joined: false,
    };

    this.handlers = {
      onOpen: options.onOpen || (() => {}),
      onClose: options.onClose || (() => {}),
      onError: options.onError || (() => {}),
      onRawMessage: options.onRawMessage || (() => {}),
      onLoginSuccess: options.onLoginSuccess || (() => {}),
      onLoginError: options.onLoginError || (() => {}),
      onJoinSuccess: options.onJoinSuccess || (() => {}),
      onReconnectInfo: options.onReconnectInfo || (() => {}),
      onEndGame: options.onEndGame || (() => {}),
      onUpdateMatch: options.onUpdateMatch || (() => {}),
      onGameMessage: options.onGameMessage || (() => {}),
    };
  }

  connect() {
    if (!this.wsUrl) {
      throw new Error("Missing wsUrl");
    }
    if (!this.nickname) {
      throw new Error("Missing nickname");
    }
    if (!this.sessionKey) {
      throw new Error("Missing sessionKey");
    }

    this.socket = new WebSocket(this.wsUrl);
    this.socket.binaryType = "arraybuffer";
    this.state.socket = "connecting";

    this.socket.addEventListener("open", () => {
      this.state.socket = "open";
      this.handlers.onOpen();
      this.sendCoreLogin();
    });

    this.socket.addEventListener("message", async (event) => {
      const bytes = await normalizeIncomingBytes(event.data);

      if (!bytes) {
        return;
      }

      const packet = decodeServerPacket(bytes);
      this.handlers.onRawMessage(packet, bytes);
      this.handlePacket(packet, bytes);
    });

    this.socket.addEventListener("close", (event) => {
      this.state.socket = "closed";
      this.handlers.onClose(event);
    });

    this.socket.addEventListener("error", (event) => {
      this.handlers.onError(event);
    });
  }

  disconnect() {
    if (this.socket) {
      this.socket.close();
    }
  }

  sendCoreLogin() {
    this.ensureOpenSocket();
    this.state.login = "login-sent";

    const body = concatBytes(
      encodeBzString(this.nickname),
      encodeBzString(this.sessionKey)
    );

    this.sendPacket(1, BacayCmd.LOGIN, body);
  }

  joinRoom() {
    this.ensureOpenSocket();

    if (this.joinConfig.mode === "by-room-id") {
      const roomId = this.joinConfig.roomId || 0;
      const password = this.joinConfig.password || "";
      const body = concatBytes(
        encodeInt32(roomId),
        encodeBzString(password)
      );
      this.sendPacket(1, BacayCmd.JOIN_BY_ROOM_ID, body);
      return;
    }

    const body = concatBytes(
      encodeInt32(this.joinConfig.moneyType || 0),
      encodeInt32(this.joinConfig.maxUserPerRoom || 8),
      encodeInt64(this.joinConfig.moneyBet || 1000),
      encodeInt32(this.joinConfig.rule || 0)
    );

    this.sendPacket(1, BacayCmd.JOIN_BY_BET, body);
  }

  requestRoomList(input) {
    this.ensureOpenSocket();

    const body = concatBytes(
      encodeInt32(input.moneyType || 0),
      encodeInt32(input.maxUserPerRoom || 8),
      encodeInt64(input.moneyBet || 1000),
      encodeInt32(input.rule || 0),
      encodeInt32(input.from || 0),
      encodeInt32(input.to || 20)
    );

    this.sendPacket(1, BacayCmd.ROOM_LIST, body);
  }

  sendDatCuoc(rate) {
    this.ensureJoined();
    this.sendPacket(1, BacayCmd.DAT_CUOC, encodeInt32(rate));
  }

  sendVaoGa() {
    this.ensureJoined();
    this.sendPacket(1, BacayCmd.VAO_GA, new Uint8Array(0));
  }

  sendKeCua(chair, rate) {
    this.ensureJoined();
    this.sendPacket(1, BacayCmd.KE_CUA, concatBytes(encodeInt32(chair), encodeInt32(rate)));
  }

  sendDanhBien(chair, rate) {
    this.ensureJoined();
    this.sendPacket(1, BacayCmd.YEU_CAU_DANH_BIEN, concatBytes(encodeInt32(chair), encodeInt32(rate)));
  }

  sendDongYDanhBien(chair) {
    this.ensureJoined();
    this.sendPacket(1, BacayCmd.DONG_Y_DANH_BIEN, encodeInt32(chair));
  }

  sendMoBai() {
    this.ensureJoined();
    this.sendPacket(1, BacayCmd.MO_BAI, new Uint8Array(0));
  }

  sendDangKyThoatPhong() {
    this.ensureJoined();
    this.sendPacket(1, BacayCmd.DANG_KY_THOAT_PHONG, new Uint8Array(0));
  }

  sendDangKyChoiTiep() {
    this.ensureJoined();
    this.sendPacket(1, BacayCmd.DANG_KY_CHOI_TIEP, new Uint8Array(0));
  }

  sendPacket(controllerId, actionId, body) {
    this.ensureOpenSocket();
    const packet = encodeWsPacket(controllerId, actionId, body);
    this.socket.send(packet.buffer);
  }

  handlePacket(packet, rawBytes) {
    const cmd = packet.cmd;

    if (cmd === BacayCmd.LOGIN) {
      const loginCode = rawBytes[3];

      if (loginCode === 0) {
        this.state.login = "login-ok";
        this.handlers.onLoginSuccess(packet, rawBytes);
        this.joinRoom();
      } else {
        this.state.login = "login-fail";
        this.handlers.onLoginError(loginCode, packet, rawBytes);
      }
      return;
    }

    if (cmd === BacayCmd.JOIN_ROOM_SUCCESS) {
      this.state.joined = true;
      this.handlers.onJoinSuccess(packet, rawBytes);
      return;
    }

    if (cmd === BacayCmd.THONG_TIN_BAN_CHOI) {
      this.handlers.onReconnectInfo(packet, rawBytes);
      return;
    }

    if (cmd === BacayCmd.KET_THUC) {
      this.handlers.onEndGame(packet, rawBytes);
      return;
    }

    if (cmd === BacayCmd.CMD_SEND_UPDATE_MATCH) {
      this.handlers.onUpdateMatch(packet, rawBytes);
      return;
    }

    if (cmd >= 3101 && cmd <= 3123) {
      this.handlers.onGameMessage(packet, rawBytes);
    }
  }

  ensureOpenSocket() {
    if (!this.socket || this.socket.readyState !== WebSocket.OPEN) {
      throw new Error("Socket is not open");
    }
  }

  ensureJoined() {
    this.ensureOpenSocket();
    if (!this.state.joined) {
      throw new Error("You must wait for 3118 before sending Bacay commands");
    }
  }
}

function encodeWsPacket(controllerId, actionId, body) {
  const output = new Uint8Array(6 + body.length);
  output[0] = 0x00;
  output[1] = 0x00;
  output[2] = 0x00;
  output[3] = controllerId & 0xff;
  writeUInt16BE(output, 4, actionId);
  output.set(body, 6);
  return output;
}

function decodeServerPacket(bytes) {
  if (bytes.length >= 3) {
    return {
      cmd: readUInt16BE(bytes, 1),
      rawHex: toHex(bytes),
    };
  }

  return {
    cmd: null,
    rawHex: toHex(bytes),
  };
}

function encodeBzString(value) {
  const text = new TextEncoder().encode(value || "");
  const out = new Uint8Array(2 + text.length);
  writeUInt16BE(out, 0, text.length);
  out.set(text, 2);
  return out;
}

function encodeInt32(value) {
  const out = new Uint8Array(4);
  const view = new DataView(out.buffer);
  view.setInt32(0, Number(value) || 0, false);
  return out;
}

function encodeInt64(value) {
  const out = new Uint8Array(8);
  const view = new DataView(out.buffer);
  view.setBigInt64(0, BigInt(value), false);
  return out;
}

function writeUInt16BE(bytes, offset, value) {
  bytes[offset] = (value >> 8) & 0xff;
  bytes[offset + 1] = value & 0xff;
}

function readUInt16BE(bytes, offset) {
  return ((bytes[offset] << 8) | bytes[offset + 1]) >>> 0;
}

function concatBytes(...chunks) {
  const total = chunks.reduce((sum, chunk) => sum + chunk.length, 0);
  const out = new Uint8Array(total);
  let offset = 0;

  for (const chunk of chunks) {
    out.set(chunk, offset);
    offset += chunk.length;
  }

  return out;
}

function toHex(bytes) {
  return Array.from(bytes, (item) => item.toString(16).padStart(2, "0")).join("");
}

async function normalizeIncomingBytes(data) {
  if (!data) {
    return null;
  }

  if (data instanceof Uint8Array) {
    return data;
  }

  if (data instanceof ArrayBuffer) {
    return new Uint8Array(data);
  }

  if (typeof Blob !== "undefined" && data instanceof Blob) {
    return new Uint8Array(await data.arrayBuffer());
  }

  if (typeof data.arrayBuffer === "function") {
    return new Uint8Array(await data.arrayBuffer());
  }

  return null;
}

function getGlobalScope() {
  if (typeof globalThis !== "undefined") {
    return globalThis;
  }
  if (typeof window !== "undefined") {
    return window;
  }
  if (typeof global !== "undefined") {
    return global;
  }
  return {};
}

function readBool(value, fallback) {
  if (value === undefined || value === "") {
    return fallback;
  }
  return ["1", "true", "yes", "on"].includes(String(value).toLowerCase());
}

function readNumber(value, fallback) {
  if (value === undefined || value === "") {
    return fallback;
  }
  const parsed = Number(value);
  return Number.isFinite(parsed) ? parsed : fallback;
}

function parseEnvFile(text) {
  const out = {};
  const lines = String(text || "").split(/\r?\n/);

  for (const line of lines) {
    const trimmed = line.trim();
    if (!trimmed || trimmed.startsWith("#")) {
      continue;
    }

    const index = trimmed.indexOf("=");
    if (index < 0) {
      continue;
    }

    const key = trimmed.slice(0, index).trim();
    const value = trimmed.slice(index + 1).trim();
    out[key] = value;
  }

  return out;
}

function loadNodeEnvFile() {
  if (typeof process === "undefined" || !process.versions || !process.versions.node) {
    return {};
  }

  try {
    const fs = require("fs");
    const path = require("path");
    const envPath = path.resolve(process.cwd(), ".env");

    if (!fs.existsSync(envPath)) {
      return {};
    }

    return parseEnvFile(fs.readFileSync(envPath, "utf8"));
  } catch (error) {
    return {};
  }
}

function resolveDemoConfig() {
  const fileEnv = loadNodeEnvFile();
  const procEnv = typeof process !== "undefined" ? process.env : {};

  const getValue = (name, fallback = "") => {
    if (procEnv && procEnv[name] !== undefined && procEnv[name] !== "") {
      return procEnv[name];
    }
    if (fileEnv[name] !== undefined && fileEnv[name] !== "") {
      return fileEnv[name];
    }
    return fallback;
  };

  return {
    wsUrl: getValue("BACAY_WS_URL", `ws://127.0.0.1:${getValue("HOST_WS_PORT", "21044")}/websocket`),
    nickname: getValue("BACAY_NICKNAME", ""),
    sessionKey: getValue("BACAY_SESSION_KEY", ""),
    joinConfig: {
      mode: getValue("BACAY_JOIN_MODE", "by-bet"),
      moneyType: readNumber(getValue("BACAY_MONEY_TYPE", "0"), 0),
      maxUserPerRoom: readNumber(getValue("BACAY_MAX_USER_PER_ROOM", "8"), 8),
      moneyBet: readNumber(getValue("BACAY_MONEY_BET", "1000"), 1000),
      rule: readNumber(getValue("BACAY_RULE", "0"), 0),
      roomId: readNumber(getValue("BACAY_ROOM_ID", "0"), 0),
      password: getValue("BACAY_ROOM_PASSWORD", ""),
    },
    autoExitAfterJoin: readBool(getValue("BACAY_AUTO_EXIT_AFTER_JOIN", "false"), false),
    runMs: readNumber(getValue("BACAY_RUN_MS", "15000"), 15000),
  };
}

function createDemoClient(config) {
  return new BacayFrontendClient({
    wsUrl: config.wsUrl,
    nickname: config.nickname,
    sessionKey: config.sessionKey,
    joinConfig: config.joinConfig,
    onOpen() {
      console.log("[open] socket connected");
    },
    onClose(event) {
      console.log("[close] socket closed", event && event.code ? `code=${event.code}` : "");
    },
    onError(error) {
      console.error("[error] socket error", error && error.message ? error.message : error);
    },
    onRawMessage(packet) {
      console.log(`[recv] cmd=${packet.cmd} hex=${packet.rawHex}`);
    },
    onLoginSuccess() {
      console.log("[login] success");
    },
    onLoginError(code) {
      console.error(`[login] failed with code=${code}`);
    },
    onJoinSuccess() {
      console.log("[join] received 3118 JOIN_ROOM_SUCCESS");
      if (config.autoExitAfterJoin) {
        console.log("[join] auto send 3111 DANG_KY_THOAT_PHONG");
        demoClient.sendDangKyThoatPhong();
      }
    },
    onReconnectInfo() {
      console.log("[sync] received 3110 THONG_TIN_BAN_CHOI");
    },
    onEndGame() {
      console.log("[game] received 3103 KET_THUC");
    },
    onUpdateMatch() {
      console.log("[game] received 3123 CMD_SEND_UPDATE_MATCH");
    },
    onGameMessage(packet) {
      console.log(`[game] cmd=${packet.cmd}`);
    },
  });
}

let demoClient = null;

function runNodeDemo() {
  const config = resolveDemoConfig();

  console.log("Bacay frontend demo");
  console.log(`- wsUrl: ${config.wsUrl}`);
  console.log(`- hasNickname: ${Boolean(config.nickname)}`);
  console.log(`- hasSessionKey: ${Boolean(config.sessionKey)}`);
  console.log(`- joinMode: ${config.joinConfig.mode}`);

  if (!config.nickname || !config.sessionKey) {
    console.error("Missing BACAY_NICKNAME or BACAY_SESSION_KEY.");
    console.error("Export them in shell before running this file, or add them to .env.");
    process.exitCode = 1;
    return;
  }

  demoClient = createDemoClient(config);
  demoClient.connect();

  setTimeout(() => {
    if (demoClient) {
      console.log("[demo] stop client");
      demoClient.disconnect();
    }
  }, config.runMs);
}

/*
 * Example usage:
 *
 * const client = new BacayFrontendClient({
 *   wsUrl: "ws://127.0.0.1:21044/websocket",
 *   nickname: auth.nickname,
 *   sessionKey: auth.sessionKey,
 *   joinConfig: {
 *     mode: "by-bet",
 *     moneyType: 0,
 *     maxUserPerRoom: 8,
 *     moneyBet: 1000,
 *     rule: 0,
 *   },
 *   onOpen() {
 *     console.log("socket opened");
 *   },
 *   onLoginSuccess(packet) {
 *     console.log("login success", packet);
 *   },
 *   onLoginError(code) {
 *     console.error("login error", code);
 *   },
 *   onJoinSuccess(packet, rawBytes) {
 *     console.log("received 3118, now bootstrap store", packet, rawBytes);
 *   },
 *   onReconnectInfo(packet) {
 *     console.log("received 3110, should full-sync store", packet);
 *   },
 *   onGameMessage(packet) {
 *     console.log("bacay cmd", packet.cmd, packet.rawHex);
 *   },
 * });
 *
 * client.connect();
 */
const globalScope = getGlobalScope();
globalScope.BacayCmd = BacayCmd;
globalScope.BacayFrontendClient = BacayFrontendClient;

if (typeof module !== "undefined" && module.exports) {
  module.exports = {
    BacayCmd,
    BacayFrontendClient,
    encodeWsPacket,
    encodeBzString,
    encodeInt32,
    encodeInt64,
    decodeServerPacket,
    resolveDemoConfig,
  };
}

if (typeof process !== "undefined" && process.versions && process.versions.node && require.main === module) {
  runNodeDemo();
}
