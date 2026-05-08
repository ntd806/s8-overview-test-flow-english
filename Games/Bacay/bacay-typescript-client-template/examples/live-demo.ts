import fs from "node:fs";
import path from "node:path";

import { BacayFrontendClient, BacayCmd, BacayPacket } from "../src";

type DemoUserMeta = {
  userId: string;
  username: string;
  displayName: string;
  dbPlayerId: string;
  deviceId: string;
  ipAddress: string;
  platform: string;
};

type DemoLogRecord = {
  ts: string;
  event: string;
  pid: number;
  wsUrl: string;
  nickname: string;
  traceId: string;
  sessionKeySuffix: string;
  user: DemoUserMeta;
  roomConfig: {
    moneyType: number;
    maxUserPerRoom: number;
    moneyBet: number;
    rule: number;
  };
  state: {
    connected: boolean;
    joined: boolean;
    round: number;
    packets: number;
  };
  data?: Record<string, unknown>;
};

function getRequiredEnv(name: string): string {
  const value = process.env[name]?.trim();
  if (!value) {
    throw new Error(`Missing required environment variable: ${name}`);
  }

  return value;
}

function getOptionalEnv(name: string, fallback: string): string {
  return process.env[name]?.trim() || fallback;
}

function getOptionalNumberEnv(name: string, fallback: number): number {
  const raw = process.env[name]?.trim();
  if (!raw) return fallback;

  const parsed = Number(raw);
  return Number.isFinite(parsed) ? parsed : fallback;
}

function getOptionalBooleanEnv(name: string, fallback: boolean): boolean {
  const raw = process.env[name]?.trim().toLowerCase();
  if (!raw) return fallback;
  return raw === "1" || raw === "true" || raw === "yes";
}

function makeTraceId(): string {
  const seed = `${Date.now()}-${Math.random().toString(36).slice(2, 10)}`;
  return `bacay-demo-${seed}`;
}

function getCmdName(cmd: number | null): string {
  if (cmd === null) return "UNKNOWN";

  const entry = Object.entries(BacayCmd).find(
    ([key, value]) => typeof value === "number" && value === cmd && Number.isNaN(Number(key))
  );

  return entry?.[0] || `CMD_${cmd}`;
}

const wsUrl = getRequiredEnv("BACAY_WS_URL");
const nickname = getRequiredEnv("BACAY_NICKNAME");
const sessionKey = getRequiredEnv("BACAY_SESSION_KEY");
const traceId = getOptionalEnv("BACAY_TRACE_ID", makeTraceId());

const roomConfig = {
  moneyType: getOptionalNumberEnv("BACAY_MONEY_TYPE", 0),
  maxUserPerRoom: getOptionalNumberEnv("BACAY_MAX_USER_PER_ROOM", 8),
  moneyBet: getOptionalNumberEnv("BACAY_MONEY_BET", 1000),
  rule: getOptionalNumberEnv("BACAY_RULE", 0),
};

const reconnectConfig = {
  enabled: getOptionalBooleanEnv("BACAY_RECONNECT_ENABLED", true),
  maxAttempts: getOptionalNumberEnv("BACAY_RECONNECT_MAX_ATTEMPTS", 1000),
  baseDelayMs: getOptionalNumberEnv("BACAY_RECONNECT_BASE_DELAY_MS", 1000),
  maxDelayMs: getOptionalNumberEnv("BACAY_RECONNECT_MAX_DELAY_MS", 10000),
};

const heartbeatMs = getOptionalNumberEnv("BACAY_HEARTBEAT_MS", 15000);
const autoBet = getOptionalNumberEnv("BACAY_AUTO_BET", roomConfig.moneyBet);
const autoVaoGa = getOptionalBooleanEnv("BACAY_AUTO_VAO_GA", true);
const autoMoBaiDelayMs = getOptionalNumberEnv("BACAY_AUTO_MO_BAI_DELAY_MS", 1500);
const autoDanhBienChair = getOptionalNumberEnv("BACAY_AUTO_DANH_BIEN_CHAIR", -1);
const autoDanhBienRate = getOptionalNumberEnv("BACAY_AUTO_DANH_BIEN_RATE", 0);
const autoKeCuaChair = getOptionalNumberEnv("BACAY_AUTO_KE_CUA_CHAIR", -1);
const autoKeCuaRate = getOptionalNumberEnv("BACAY_AUTO_KE_CUA_RATE", 0);

const userMeta: DemoUserMeta = {
  userId: getOptionalEnv("BACAY_USER_ID", ""),
  username: getOptionalEnv("BACAY_USERNAME", nickname),
  displayName: getOptionalEnv("BACAY_DISPLAY_NAME", nickname),
  dbPlayerId: getOptionalEnv("BACAY_DB_PLAYER_ID", ""),
  deviceId: getOptionalEnv("BACAY_DEVICE_ID", ""),
  ipAddress: getOptionalEnv("BACAY_IP_ADDRESS", ""),
  platform: getOptionalEnv("BACAY_PLATFORM", "typescript-demo"),
};

const logDir = path.resolve(getOptionalEnv("BACAY_LOG_DIR", "logs"));
const defaultLogName = `${traceId}.log`;
const logFile = path.join(logDir, getOptionalEnv("BACAY_LOG_FILE", defaultLogName));
const textLogFile = logFile.replace(/\.log$/i, ".txt");

fs.mkdirSync(logDir, { recursive: true });
const logStream = fs.createWriteStream(logFile, { flags: "a" });
const textLogStream = fs.createWriteStream(textLogFile, { flags: "a" });

let packetCount = 0;
let round = 0;
let connected = false;
let joined = false;
let didBetThisRound = false;
let didOpenThisRound = false;
let didDanhBienThisRound = false;
let didKeCuaThisRound = false;
let lastPacketAt = "";

function sessionKeySuffix(value: string): string {
  if (value.length <= 8) return value;
  return value.slice(-8);
}

function writeLog(event: string, data?: Record<string, unknown>): void {
  const record: DemoLogRecord = {
    ts: new Date().toISOString(),
    event,
    pid: process.pid,
    wsUrl,
    nickname,
    traceId,
    sessionKeySuffix: sessionKeySuffix(sessionKey),
    user: userMeta,
    roomConfig,
    state: {
      connected,
      joined,
      round,
      packets: packetCount,
    },
    data,
  };

  const line = JSON.stringify(record);
  logStream.write(`${line}\n`);
  textLogStream.write(formatTextLog(record));
  console.log(line);
}

function formatTextLog(record: DemoLogRecord): string {
  const lines = [
    `[${record.ts}] event=${record.event}`,
    `traceId=${record.traceId} pid=${record.pid}`,
    `nickname=${record.nickname} sessionKeySuffix=${record.sessionKeySuffix}`,
    `wsUrl=${record.wsUrl}`,
    `user userId=${record.user.userId || "-"} username=${record.user.username || "-"} displayName=${record.user.displayName || "-"} dbPlayerId=${record.user.dbPlayerId || "-"} deviceId=${record.user.deviceId || "-"} ipAddress=${record.user.ipAddress || "-"} platform=${record.user.platform || "-"}`,
    `room moneyType=${record.roomConfig.moneyType} maxUserPerRoom=${record.roomConfig.maxUserPerRoom} moneyBet=${record.roomConfig.moneyBet} rule=${record.roomConfig.rule}`,
    `state connected=${record.state.connected} joined=${record.state.joined} round=${record.state.round} packets=${record.state.packets}`,
  ];

  if (record.data && Object.keys(record.data).length > 0) {
    lines.push("data:");
    for (const [key, value] of Object.entries(record.data)) {
      lines.push(`  - ${key}: ${formatTextValue(value)}`);
    }
  }

  return `${lines.join("\n")}\n\n`;
}

function formatTextValue(value: unknown): string {
  if (value === null || value === undefined) return String(value);
  if (typeof value === "string") return value;
  if (typeof value === "number" || typeof value === "boolean") return String(value);
  return JSON.stringify(value);
}

function logPacket(event: string, packet: BacayPacket): void {
  packetCount += 1;
  lastPacketAt = new Date().toISOString();
  writeLog(event, {
    cmd: packet.cmd,
    cmdName: getCmdName(packet.cmd),
    rawHex: packet.rawHex,
    size: packet.rawBytes.length,
  });
}

function resetRoundFlags(): void {
  didBetThisRound = false;
  didOpenThisRound = false;
  didDanhBienThisRound = false;
  didKeCuaThisRound = false;
}

function safeAction(action: string, execute: () => void, extra?: Record<string, unknown>): void {
  try {
    execute();
    writeLog("client_action", {
      action,
      ...extra,
    });
  } catch (error) {
    writeLog("client_action_error", {
      action,
      message: error instanceof Error ? error.message : String(error),
      ...extra,
    });
  }
}

writeLog("process_start", {
  logFile,
  textLogFile,
  heartbeatMs,
  reconnectConfig,
  autoBet,
  autoVaoGa,
  autoMoBaiDelayMs,
  autoDanhBienChair,
  autoDanhBienRate,
  autoKeCuaChair,
  autoKeCuaRate,
});

const client = new BacayFrontendClient({
  wsUrl,
  nickname,
  sessionKey,
  joinConfig: {
    mode: "by-bet",
    ...roomConfig,
  },
  reconnect: reconnectConfig,
  handlers: {
    onOpen() {
      connected = true;
      writeLog("socket_open");
    },
    onClose(event) {
      connected = false;
      joined = false;
      writeLog("socket_close", {
        code: event.code,
        reason: event.reason,
        wasClean: event.wasClean,
      });
    },
    onError(error) {
      writeLog("client_error", {
        code: error.code,
        message: error.message,
      });
    },
    onRawMessage(packet) {
      logPacket("raw_packet", packet);
    },
    onLoginSuccess(packet) {
      logPacket("login_success", packet);
    },
    onLoginError(error, packet) {
      writeLog("login_error", {
        code: error.code,
        message: error.message,
        packetCmd: packet?.cmd ?? null,
      });
    },
    onJoinSuccess(packet) {
      joined = true;
      resetRoundFlags();
      logPacket("join_success", packet);
      safeAction("sendDangKyChoiTiep", () => client.sendDangKyChoiTiep());
    },
    onJoinError(error, detail, packet) {
      writeLog("join_error", {
        code: error.code,
        message: error.message,
        joinFailCode: detail.joinFailCode,
        joinFailReason: detail.joinFailReason,
        packetCmd: packet?.cmd ?? null,
      });
    },
    onReconnectStart(attempt, delayMs) {
      writeLog("reconnect_start", {
        attempt,
        delayMs,
      });
    },
    onReconnectSuccess() {
      writeLog("reconnect_success");
    },
    onReconnectFailed(error) {
      writeLog("reconnect_failed", {
        code: error.code,
        message: error.message,
      });
    },
    onReconnectInfo(packet) {
      logPacket("reconnect_info", packet);
    },
    onEndGame(packet) {
      logPacket("end_game", packet);
      safeAction("sendDangKyChoiTiep", () => client.sendDangKyChoiTiep());
      resetRoundFlags();
    },
    onUpdateMatch(packet) {
      logPacket("update_match", packet);
    },
    onGameMessage(packet) {
      const cmdName = getCmdName(packet.cmd);
      logPacket("game_message", packet);

      if (packet.cmd === BacayCmd.BAT_DAU) {
        round += 1;
        resetRoundFlags();
        writeLog("round_start", {
          cmdName,
          round,
        });
        return;
      }

      if (packet.cmd === BacayCmd.MOI_DAT_CUOC && !didBetThisRound) {
        didBetThisRound = true;
        safeAction("sendDatCuoc", () => client.sendDatCuoc(autoBet), {
          rate: autoBet,
          round,
        });

        if (autoVaoGa) {
          safeAction("sendVaoGa", () => client.sendVaoGa(), {
            round,
          });
        }

        if (autoKeCuaChair >= 0 && autoKeCuaRate > 0 && !didKeCuaThisRound) {
          didKeCuaThisRound = true;
          safeAction("sendKeCua", () => client.sendKeCua(autoKeCuaChair, autoKeCuaRate), {
            chair: autoKeCuaChair,
            rate: autoKeCuaRate,
            round,
          });
        }

        return;
      }

      if (packet.cmd === BacayCmd.YEU_CAU_DANH_BIEN && autoDanhBienChair >= 0 && autoDanhBienRate > 0 && !didDanhBienThisRound) {
        didDanhBienThisRound = true;
        safeAction("sendDanhBien", () => client.sendDanhBien(autoDanhBienChair, autoDanhBienRate), {
          chair: autoDanhBienChair,
          rate: autoDanhBienRate,
          round,
        });
        return;
      }

      if (packet.cmd === BacayCmd.CHIA_BAI && !didOpenThisRound) {
        didOpenThisRound = true;
        setTimeout(() => {
          safeAction("sendMoBai", () => client.sendMoBai(), {
            delayMs: autoMoBaiDelayMs,
            round,
          });
        }, autoMoBaiDelayMs);
      }
    },
  },
});

const heartbeat = setInterval(() => {
  writeLog("heartbeat", {
    lastPacketAt,
  });
}, heartbeatMs);

function shutdown(reason: string): void {
  clearInterval(heartbeat);
  writeLog("process_stop", { reason });
  client.disconnect();
  logStream.end();
  textLogStream.end();
}

process.on("SIGINT", () => {
  shutdown("SIGINT");
  process.exit(0);
});

process.on("SIGTERM", () => {
  shutdown("SIGTERM");
  process.exit(0);
});

process.on("uncaughtException", (error) => {
  writeLog("uncaught_exception", {
    message: error.message,
    stack: error.stack,
  });
  shutdown("uncaughtException");
  process.exit(1);
});

process.on("unhandledRejection", (reason) => {
  writeLog("unhandled_rejection", {
    reason: reason instanceof Error ? reason.message : String(reason),
  });
});

writeLog("connect_start");
client.connect();
