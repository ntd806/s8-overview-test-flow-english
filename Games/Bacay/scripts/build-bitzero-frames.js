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

function hex(buf) {
  return Buffer.from(buf).toString("hex");
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
  const envInfo = loadScriptEnv();
  const config = resolveConfig();

  if (!config.nickname || !config.sessionKey) {
    throw new Error("Missing BACAY_NICKNAME or BACAY_SESSION_KEY in .env");
  }

  const loginContent = loginBody(config.nickname, config.sessionKey);
  const loginWs = wsFrame(1, 1, loginContent);
  const loginTcp = tcpFrame(1, 1, loginContent);

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

  const joinWs = wsFrame(1, joinActionId, joinContent);
  const roomListWs = wsFrame(
    1,
    3014,
    roomListBody(
      config.moneyType,
      config.maxUserPerRoom,
      config.moneyBet,
      config.rule,
      config.roomListFrom,
      config.roomListTo
    )
  );

  return {
    reverseVerified: {
      wsWrapper: "00 00 00 | controller(1 byte) | actionId(uint16_be) | content",
      tcpWrapper: "80 | payloadLen(uint16_be) | controller(1 byte) | actionId(uint16_be) | content",
      loginRoute: "controller=1, actionId=1",
      joinByBetRoute: "controller=1, actionId=3001",
      joinByRoomIdRoute: "controller=1, actionId=3015",
      roomListRoute: "controller=1, actionId=3014",
    },
    env: {
      loaded: envInfo.loaded,
      active: envInfo.envPath,
    },
    config: {
      joinMode: config.joinMode,
      nickname: config.nickname,
      sessionKeyLength: config.sessionKey.length,
      moneyType: config.moneyType,
      maxUserPerRoom: config.maxUserPerRoom,
      moneyBet: config.moneyBet.toString(),
      rule: config.rule,
      roomId: config.roomId,
      roomPasswordLength: config.roomPassword.length,
      roomListFrom: config.roomListFrom,
      roomListTo: config.roomListTo,
    },
    envReady: {
      BACAY_LOGIN_PACKET_HEX: hex(loginWs),
      BACAY_JOIN_PACKET_HEX: hex(joinWs),
    },
    frames: {
      loginWsHex: hex(loginWs),
      loginTcpHex: hex(loginTcp),
      roomListWsHex: hex(roomListWs),
      joinWsHex: hex(joinWs),
    },
  };
}

try {
  console.log(JSON.stringify(buildFrameSet(), null, 2));
} catch (error) {
  console.error(error.message);
  process.exit(1);
}
