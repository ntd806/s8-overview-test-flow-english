export enum BacayCmd {
  LOGIN = 1,
  JOIN_BY_BET = 3001,
  ROOM_LIST = 3014,
  JOIN_BY_ROOM_ID = 3015,

  MO_BAI = 3101,
  BAT_DAU = 3102,
  KET_THUC = 3103,
  YEU_CAU_DANH_BIEN = 3104,
  CHIA_BAI = 3105,
  KE_CUA = 3106,
  TU_DONG_BAT_DAU = 3107,
  DONG_Y_DANH_BIEN = 3108,
  DAT_CUOC = 3109,
  THONG_TIN_BAN_CHOI = 3110,
  DANG_KY_THOAT_PHONG = 3111,
  VAO_GA = 3112,
  DOI_CHUONG = 3113,
  MOI_DAT_CUOC = 3114,
  CHEAT_CARDS = 3115,
  DANG_KY_CHOI_TIEP = 3116,
  UPDATE_OWNER_ROOM = 3117,
  JOIN_ROOM_SUCCESS = 3118,
  LEAVE_GAME = 3119,
  NOTIFY_KICK_FROM_ROOM = 3120,
  NEW_USER_JOIN = 3121,
  NOTIFY_USER_GET_JACKPOT = 3122,
  CMD_SEND_UPDATE_MATCH = 3123,
}

export type BacayClientState = {
  socket: "idle" | "connecting" | "open" | "closed" | "reconnecting";
  login: "idle" | "login-sent" | "login-ok" | "login-fail";
  joined: boolean;
  reconnectAttempts: number;
};

export type JoinConfig =
  | {
      mode: "by-bet";
      moneyType?: number;
      maxUserPerRoom?: number;
      moneyBet?: number;
      rule?: number;
    }
  | {
      mode: "by-room-id";
      roomId: number;
      password?: string;
    };

export type ReconnectConfig = {
  enabled?: boolean;
  maxAttempts?: number;
  baseDelayMs?: number;
  maxDelayMs?: number;
};

export type BacayPacket = {
  cmd: number | null;
  rawHex: string;
  rawBytes: Uint8Array;
};

export type BacayClientErrorCode =
  | "MISSING_CONFIG"
  | "SOCKET_NOT_OPEN"
  | "NOT_JOINED_ROOM"
  | "LOGIN_FAILED"
  | "MAX_RECONNECT_ATTEMPTS"
  | "PACKET_DECODE_ERROR"
  | "UNKNOWN_ERROR";

export class BacayClientError extends Error {
  public code: BacayClientErrorCode;
  public cause?: unknown;

  constructor(code: BacayClientErrorCode, message: string, cause?: unknown) {
    super(message);
    this.name = "BacayClientError";
    this.code = code;
    this.cause = cause;
  }
}

export type BacayClientHandlers = {
  onOpen?: () => void;
  onClose?: (event: CloseEvent) => void;
  onError?: (error: BacayClientError) => void;
  onRawMessage?: (packet: BacayPacket) => void;
  onLoginSuccess?: (packet: BacayPacket) => void;
  onLoginError?: (error: BacayClientError, packet?: BacayPacket) => void;
  onJoinSuccess?: (packet: BacayPacket) => void;
  onReconnectStart?: (attempt: number, delayMs: number) => void;
  onReconnectSuccess?: () => void;
  onReconnectFailed?: (error: BacayClientError) => void;
  onReconnectInfo?: (packet: BacayPacket) => void;
  onEndGame?: (packet: BacayPacket) => void;
  onUpdateMatch?: (packet: BacayPacket) => void;
  onGameMessage?: (packet: BacayPacket) => void;
};

export type BacayClientOptions = {
  wsUrl: string;
  nickname: string;
  sessionKey: string;
  joinConfig?: JoinConfig;
  reconnect?: ReconnectConfig;
  handlers?: BacayClientHandlers;
};
