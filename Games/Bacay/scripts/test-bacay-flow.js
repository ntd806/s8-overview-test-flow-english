#!/usr/bin/env node

const fs = require("fs");
const path = require("path");

const SCRIPT_DIR = __dirname;
const ROOT_DIR = path.resolve(SCRIPT_DIR, "..");
const SCRIPT_ENV_PATH = path.join(SCRIPT_DIR, ".env");
const ROOT_ENV_PATH = path.join(ROOT_DIR, ".env");
const ROOM_CONFIG_PATH = path.join(ROOT_DIR, "conf", "gameroom.json");

function parseDotEnvValue(value) {
  const trimmed = value.trim();
  if (
    (trimmed.startsWith('"') && trimmed.endsWith('"')) ||
    (trimmed.startsWith("'") && trimmed.endsWith("'"))
  ) {
    return trimmed.slice(1, -1);
  }
  return value;
}

function loadDotEnvFile(filePath, { override = false, protectedKeys = new Set() } = {}) {
  if (!fs.existsSync(filePath)) {
    return false;
  }

  const raw = fs.readFileSync(filePath, "utf8").replace(/^\uFEFF/, "");
  for (const line of raw.split(/\r?\n/)) {
    const trimmed = line.trim();
    if (!trimmed || trimmed.startsWith("#")) {
      continue;
    }

    const eq = trimmed.indexOf("=");
    if (eq === -1) {
      continue;
    }

    const key = trimmed.slice(0, eq).trim();
    const value = parseDotEnvValue(trimmed.slice(eq + 1));
    if (protectedKeys.has(key)) {
      continue;
    }

    if (override || !(key in process.env)) {
      process.env[key] = value;
    }
  }
  return true;
}

function loadScriptEnv() {
  const loaded = [];
  const originalEnvKeys = new Set(Object.keys(process.env));

  if (loadDotEnvFile(ROOT_ENV_PATH, { override: false })) {
    loaded.push(ROOT_ENV_PATH);
  }

  if (loadDotEnvFile(SCRIPT_ENV_PATH, { override: true, protectedKeys: originalEnvKeys })) {
    loaded.push(SCRIPT_ENV_PATH);
  }

  return {
    loaded,
    envPath: fs.existsSync(SCRIPT_ENV_PATH) ? SCRIPT_ENV_PATH : ROOT_ENV_PATH,
  };
}

function readJson(filePath) {
  return JSON.parse(fs.readFileSync(filePath, "utf8"));
}

function pickDefined(...values) {
  for (const value of values) {
    if (value !== undefined) {
      return value;
    }
  }
  return undefined;
}

function readBool(value, fallback) {
  if (value === undefined || value === "") {
    return fallback;
  }
  return ["1", "true", "yes", "on"].includes(String(value).toLowerCase());
}

function readNumber(name, fallback, env = process.env) {
  const raw = env[name];
  if (raw === undefined || raw === "") {
    return fallback;
  }

  const value = Number(raw);
  if (!Number.isFinite(value)) {
    throw new Error(`Invalid number for ${name}: ${raw}`);
  }
  return value;
}

function readBigInt(name, fallback, env = process.env) {
  const raw = env[name];
  if (raw === undefined || raw === "") {
    return BigInt(fallback);
  }

  try {
    return BigInt(raw);
  } catch (err) {
    throw new Error(`Invalid bigint for ${name}: ${raw}`);
  }
}

function readString(name, fallback = "", env = process.env) {
  const raw = env[name];
  return raw === undefined ? fallback : raw;
}

function mask(value) {
  if (!value) {
    return "";
  }
  if (value.length <= 6) {
    return "***";
  }
  return `${value.slice(0, 3)}***${value.slice(-2)}`;
}

function hexToBuffer(value) {
  const normalized = String(value || "").replace(/\s+/g, "");
  if (!normalized) {
    return null;
  }
  return Buffer.from(normalized, "hex");
}

function u16(value) {
  const buf = Buffer.alloc(2);
  buf.writeUInt16BE(value & 0xffff, 0);
  return buf;
}

function i32(value) {
  const buf = Buffer.alloc(4);
  buf.writeInt32BE(value | 0, 0);
  return buf;
}

function i64(value) {
  const buf = Buffer.alloc(8);
  buf.writeBigInt64BE(BigInt(value), 0);
  return buf;
}

function bzString(value) {
  const data = Buffer.from(value, "utf8");
  return Buffer.concat([u16(data.length), data]);
}

function wsFrame(controllerId, actionId, content) {
  return Buffer.concat([
    Buffer.from([0x00, 0x00, 0x00]),
    Buffer.from([controllerId & 0xff]),
    u16(actionId),
    content,
  ]);
}

function tcpFrame(controllerId, actionId, content) {
  const payload = Buffer.concat([
    Buffer.from([controllerId & 0xff]),
    u16(actionId),
    content,
  ]);
  return Buffer.concat([Buffer.from([0x80]), u16(payload.length), payload]);
}

function clientWsFrame(actionId, body = Buffer.alloc(0)) {
  return Buffer.concat([Buffer.from([0x00, 0x00, 0x00, 0x01]), u16(actionId), body]);
}

function loginBody(nickname, sessionKey) {
  return Buffer.concat([bzString(nickname), bzString(sessionKey)]);
}

function joinByBetBody(moneyType, maxUserPerRoom, moneyBet, rule) {
  return Buffer.concat([i32(moneyType), i32(maxUserPerRoom), i64(moneyBet), i32(rule)]);
}

function joinByRoomIdBody(roomId, password) {
  return Buffer.concat([i32(roomId), bzString(password)]);
}

function roomListBody(moneyType, maxUserPerRoom, moneyBet, rule, from, to) {
  return Buffer.concat([
    i32(moneyType),
    i32(maxUserPerRoom),
    i64(moneyBet),
    i32(rule),
    i32(from),
    i32(to),
  ]);
}

function detectCandidateCommand(buf) {
  if (buf.length >= 6 && buf[0] === 0x00 && buf[1] === 0x00 && buf[2] === 0x00) {
    return buf.readUInt16BE(4);
  }
  if (buf.length >= 3) {
    return buf.readUInt16BE(1);
  }
  return null;
}

function resolveConfig() {
  const roomConfig = fs.existsSync(ROOM_CONFIG_PATH) ? readJson(ROOM_CONFIG_PATH) : null;
  const firstRoom = roomConfig?.roomList?.[0] || {};
  const fallbackRoom = {
    moneyType: pickDefined(firstRoom.moneyType, 1),
    maxUserPerRoom: pickDefined(firstRoom.maxUserPerRoom, 4),
    moneyBet: pickDefined(firstRoom.moneyBet, 0),
    rule: pickDefined(firstRoom.rule, 1),
  };

  return {
    nickname: readString("BACAY_NICKNAME"),
    sessionKey: readString("BACAY_SESSION_KEY"),
    joinMode: readString("BACAY_JOIN_MODE", "by-bet"),
    moneyType: readNumber("BACAY_MONEY_TYPE", fallbackRoom.moneyType),
    maxUserPerRoom: readNumber("BACAY_MAX_USER_PER_ROOM", fallbackRoom.maxUserPerRoom),
    moneyBet: readBigInt("BACAY_MONEY_BET", fallbackRoom.moneyBet),
    rule: readNumber("BACAY_RULE", fallbackRoom.rule),
    roomId: readNumber("BACAY_ROOM_ID", 1),
    roomPassword: readString("BACAY_ROOM_PASSWORD", ""),
    roomListFrom: readNumber("BACAY_ROOM_LIST_FROM", 0),
    roomListTo: readNumber("BACAY_ROOM_LIST_TO", 20),
  };
}

function buildFrameSet() {
  const config = resolveConfig();

  if (!config.nickname || !config.sessionKey) {
    throw new Error("Missing BACAY_NICKNAME or BACAY_SESSION_KEY in .env");
  }

  const loginContent = loginBody(config.nickname, config.sessionKey);
  const loginWs = wsFrame(1, 1, loginContent);

  let joinActionId;
  let joinContent;

  if (config.joinMode === "by-room-id") {
    joinActionId = 3015;
    joinContent = joinByRoomIdBody(config.roomId, config.roomPassword);
  } else if (config.joinMode === "by-bet") {
    joinActionId = 3001;
    joinContent = joinByBetBody(
      config.moneyType,
      config.maxUserPerRoom,
      config.moneyBet,
      config.rule
    );
  } else {
    throw new Error(`Unsupported BACAY_JOIN_MODE: ${config.joinMode}`);
  }

  return {
    envReady: {
      BACAY_LOGIN_PACKET_HEX: Buffer.from(loginWs).toString("hex"),
      BACAY_JOIN_PACKET_HEX: Buffer.from(wsFrame(1, joinActionId, joinContent)).toString("hex"),
    },
  };
}

loadScriptEnv();

const generated = buildFrameSet();
const wsUrl = process.env.BACAY_WS_URL || "ws://127.0.0.1:21044/websocket";
const nickname = process.env.BACAY_NICKNAME || "";
const sessionKey = process.env.BACAY_SESSION_KEY || "";
const loginPacketHex = process.env.BACAY_LOGIN_PACKET_HEX || generated.envReady.BACAY_LOGIN_PACKET_HEX;
const joinPacketHex = process.env.BACAY_JOIN_PACKET_HEX || generated.envReady.BACAY_JOIN_PACKET_HEX;
const autoLogin = readBool(process.env.BACAY_AUTO_LOGIN, true);
const autoJoin = readBool(process.env.BACAY_AUTO_JOIN, true);
const joinDelayMs = readNumber("BACAY_JOIN_DELAY_MS", 1500);
const runMs = readNumber("BACAY_RUN_MS", 15000);
const postJoinCommandId = readNumber("BACAY_POST_JOIN_COMMAND_ID", 3111);
const postJoinCommandDelayMs = readNumber("BACAY_POST_JOIN_COMMAND_DELAY_MS", 2500);
const postJoinCommandBodyHex = process.env.BACAY_POST_JOIN_COMMAND_BODY_HEX || "";
const postJoinCommandPacketHex =
  process.env.BACAY_POST_JOIN_COMMAND_PACKET_HEX ||
  (postJoinCommandId > 0
    ? clientWsFrame(postJoinCommandId, hexToBuffer(postJoinCommandBodyHex) || Buffer.alloc(0)).toString(
        "hex"
      )
    : "");

const state = {
  opened: false,
  loginSent: false,
  joinSent: false,
  postJoinCommandSent: false,
  sawJoin3118: false,
  sawLeave3119: false,
  packetCount: 0,
  hasLoginPacketHex: Boolean(loginPacketHex),
  hasJoinPacketHex: Boolean(joinPacketHex),
};

console.log("Bacay flow test client");
console.log("Flow: open socket -> login -> join room -> wait 3118");
console.log("");
console.log("Config:");
console.log(`- wsUrl: ${wsUrl}`);
console.log(`- nickname: ${mask(nickname)}`);
console.log(`- sessionKey: ${mask(sessionKey)}`);
console.log(`- hasLoginPacketHex: ${state.hasLoginPacketHex}`);
console.log(`- hasJoinPacketHex: ${state.hasJoinPacketHex}`);
console.log(`- interactive: false`);
console.log(`- runMs: ${runMs}`);
console.log(`- autoLogin: ${autoLogin}`);
console.log(`- autoJoin: ${autoJoin}`);
console.log(`- joinDelayMs: ${joinDelayMs}`);
console.log(`- postJoinCommandId: ${postJoinCommandId || "(none)"}`);
console.log("");
console.log(`[batch] Non-interactive mode. Will stop after ${runMs}ms.`);

const ws = new WebSocket(wsUrl);
let joinTimer = null;
let sawOpen = false;
let manualShutdown = false;

ws.binaryType = "arraybuffer";

ws.addEventListener("open", () => {
  sawOpen = true;
  state.opened = true;
  console.log(`[open] Connected -> ${wsUrl}`);

  if (autoLogin && loginPacketHex) {
    ws.send(hexToBuffer(loginPacketHex));
    state.loginSent = true;
    console.log(`[send] login -> ${loginPacketHex}`);
  }

  if (autoJoin && joinPacketHex) {
    joinTimer = setTimeout(() => {
      if (ws.readyState === WebSocket.OPEN) {
        ws.send(hexToBuffer(joinPacketHex));
        state.joinSent = true;
        console.log(`[send] join -> ${joinPacketHex}`);
      }
    }, joinDelayMs);
  }
});

ws.addEventListener("message", (event) => {
  const buf = Buffer.from(event.data);
  const cmd = detectCandidateCommand(buf);
  state.packetCount += 1;
  if (cmd === 3118) {
    state.sawJoin3118 = true;
    if (postJoinCommandPacketHex && !state.postJoinCommandSent) {
      setTimeout(() => {
        if (ws.readyState === WebSocket.OPEN) {
          ws.send(hexToBuffer(postJoinCommandPacketHex));
          state.postJoinCommandSent = true;
          console.log(`[send] post-join command -> ${postJoinCommandPacketHex}`);
        }
      }, postJoinCommandDelayMs);
    }
  }
  if (cmd === 3119) {
    state.sawLeave3119 = true;
  }
  console.log(`[recv] hex=${buf.toString("hex")} cmd=${cmd ?? "?"}`);
});

ws.addEventListener("error", () => {
  console.error("[error] WebSocket error: Received network error or non-101 status code.");
});

ws.addEventListener("close", () => {
  if (joinTimer) {
    clearTimeout(joinTimer);
  }
  if (!sawOpen) {
    console.error("[error] WebSocket error: Connection was closed before it was established.");
  } else if (!manualShutdown) {
    console.error("[close] WebSocket closed by server.");
  }
});

setTimeout(() => {
  if (joinTimer) {
    clearTimeout(joinTimer);
  }
  manualShutdown = true;
  if (ws.readyState === WebSocket.OPEN || ws.readyState === WebSocket.CONNECTING) {
    ws.close();
  }
  console.log(JSON.stringify(state, null, 2));
}, runMs);
