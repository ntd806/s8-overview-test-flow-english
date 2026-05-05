import { BacayFrontendClient } from "../src";

let step = 1;

function logStep(message: string): void {
  console.log(`[step ${step}] ${message}`);
  step += 1;
}

function logInfo(message: string): void {
  console.log(`[info] ${message}`);
}

function getRequiredEnv(name: string): string {
  const value = process.env[name]?.trim();
  if (!value) {
    throw new Error(`Missing required environment variable: ${name}`);
  }

  return value;
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

const wsUrl = getRequiredEnv("BACAY_WS_URL");
const nickname = getRequiredEnv("BACAY_NICKNAME");
const sessionKey = getRequiredEnv("BACAY_SESSION_KEY");
const timeoutMs = getOptionalNumberEnv("BACAY_TIMEOUT_MS", 20000);
const joinConfig = {
  mode: "by-bet" as const,
  moneyType: getOptionalNumberEnv("BACAY_MONEY_TYPE", 0),
  maxUserPerRoom: getOptionalNumberEnv("BACAY_MAX_USER_PER_ROOM", 8),
  moneyBet: getOptionalNumberEnv("BACAY_MONEY_BET", 1000),
  rule: getOptionalNumberEnv("BACAY_RULE", 0),
};
const reconnectConfig = {
  enabled: getOptionalBooleanEnv("BACAY_RECONNECT_ENABLED", true),
  maxAttempts: getOptionalNumberEnv("BACAY_RECONNECT_MAX_ATTEMPTS", 5),
  baseDelayMs: getOptionalNumberEnv("BACAY_RECONNECT_BASE_DELAY_MS", 1000),
  maxDelayMs: getOptionalNumberEnv("BACAY_RECONNECT_MAX_DELAY_MS", 10000),
};

logStep("loaded environment variables");
logInfo(`wsUrl=${wsUrl}`);
logInfo(`nickname=${nickname}`);
logInfo(`timeoutMs=${timeoutMs}`);
logInfo(
  `joinConfig mode=${joinConfig.mode} moneyType=${joinConfig.moneyType} maxUserPerRoom=${joinConfig.maxUserPerRoom} moneyBet=${joinConfig.moneyBet} rule=${joinConfig.rule}`
);
logInfo(
  `reconnect enabled=${reconnectConfig.enabled} maxAttempts=${reconnectConfig.maxAttempts} baseDelayMs=${reconnectConfig.baseDelayMs} maxDelayMs=${reconnectConfig.maxDelayMs}`
);

let finished = false;

const timeout = setTimeout(() => {
  if (finished) return;
  finished = true;
  console.error(`[timeout] no join success after ${timeoutMs}ms`);
  client.disconnect();
  process.exit(1);
}, timeoutMs);

logStep("creating BacayFrontendClient");

const client = new BacayFrontendClient({
  wsUrl,
  nickname,
  sessionKey,
  joinConfig,
  reconnect: reconnectConfig,
  handlers: {
    onOpen() {
      logStep("socket opened, client will send core login automatically");
    },
    onClose(event) {
      console.log(`[close] code=${event.code} reason=${event.reason}`);
    },
    onError(error) {
      console.error(`[error] code=${error.code} message=${error.message}`);
    },
    onRawMessage(packet) {
      console.log(`[recv] cmd=${packet.cmd} hex=${packet.rawHex}`);
    },
    onLoginSuccess() {
      logStep("login success, client will send join room automatically");
    },
    onLoginError(error) {
      console.error(`[login] failed ${error.message}`);
    },
    onJoinSuccess() {
      if (finished) return;
      finished = true;
      clearTimeout(timeout);
      logStep("join room success via cmd=3118");
      client.disconnect();
      process.exit(0);
    },
    onReconnectStart(attempt, delayMs) {
      logInfo(`reconnect attempt=${attempt} delay=${delayMs}ms`);
    },
    onReconnectSuccess() {
      logInfo("reconnect success");
    },
    onReconnectFailed(error) {
      console.error(`[reconnect] failed ${error.message}`);
    },
    onReconnectInfo(packet) {
      logInfo(`sync packet cmd=${packet.cmd}`);
    },
    onGameMessage(packet) {
      logInfo(`game packet cmd=${packet.cmd}`);
    },
  },
});

logStep("calling client.connect()");
client.connect();
