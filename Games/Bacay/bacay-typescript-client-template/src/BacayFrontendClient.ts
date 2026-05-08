import {
  BacayClientError,
  BacayClientOptions,
  BacayClientState,
  BacayCmd,
  BacayPacket,
  JoinFailCode,
  JoinFailReason,
  ReconnectConfig,
} from "./types";

import {
  concatBytes,
  decodeServerPacket,
  encodeBzString,
  encodeInt32,
  encodeInt64,
  encodeWsPacket,
  normalizeIncomingBytes,
} from "./utils";

const DEFAULT_RECONNECT: Required<ReconnectConfig> = {
  enabled: true,
  maxAttempts: 5,
  baseDelayMs: 1000,
  maxDelayMs: 10000,
};

const JOIN_FAIL_CODE_MAP: Record<JoinFailCode, JoinFailReason> = {
  1: "INFO_ERROR",
  2: "ROOM_ERROR",
  3: "MONEY_ERROR",
  4: "JOIN_ERROR",
};

export class BacayFrontendClient {
  private socket: WebSocket | null = null;
  private options: BacayClientOptions;
  private reconnectConfig: Required<ReconnectConfig>;
  private manualClose = false;
  private reconnectTimer: ReturnType<typeof setTimeout> | null = null;

  public state: BacayClientState = {
    socket: "idle",
    login: "idle",
    joined: false,
    reconnectAttempts: 0,
  };

  constructor(options: BacayClientOptions) {
    this.options = {
      ...options,
      joinConfig: options.joinConfig || {
        mode: "by-bet",
        moneyType: 0,
        maxUserPerRoom: 8,
        moneyBet: 1000,
        rule: 0,
      },
      handlers: options.handlers || {},
    };

    this.reconnectConfig = {
      ...DEFAULT_RECONNECT,
      ...(options.reconnect || {}),
    };

    this.validateConfig();
  }

  connect(): void {
    this.manualClose = false;
    this.openSocket();
  }

  disconnect(): void {
    this.manualClose = true;
    this.clearReconnectTimer();

    if (this.socket) {
      this.socket.close();
      this.socket = null;
    }

    this.state.socket = "closed";
    this.state.joined = false;
  }

  sendDatCuoc(rate: number): void {
    this.ensureJoined();
    this.sendPacket(1, BacayCmd.DAT_CUOC, encodeInt32(rate));
  }

  sendVaoGa(): void {
    this.ensureJoined();
    this.sendPacket(1, BacayCmd.VAO_GA, new Uint8Array(0));
  }

  sendKeCua(chair: number, rate: number): void {
    this.ensureJoined();
    this.sendPacket(1, BacayCmd.KE_CUA, concatBytes(encodeInt32(chair), encodeInt32(rate)));
  }

  sendDanhBien(chair: number, rate: number): void {
    this.ensureJoined();
    this.sendPacket(1, BacayCmd.YEU_CAU_DANH_BIEN, concatBytes(encodeInt32(chair), encodeInt32(rate)));
  }

  sendDongYDanhBien(chair: number): void {
    this.ensureJoined();
    this.sendPacket(1, BacayCmd.DONG_Y_DANH_BIEN, encodeInt32(chair));
  }

  sendMoBai(): void {
    this.ensureJoined();
    this.sendPacket(1, BacayCmd.MO_BAI, new Uint8Array(0));
  }

  sendDangKyThoatPhong(): void {
    this.ensureJoined();
    this.sendPacket(1, BacayCmd.DANG_KY_THOAT_PHONG, new Uint8Array(0));
  }

  sendDangKyChoiTiep(): void {
    this.ensureJoined();
    this.sendPacket(1, BacayCmd.DANG_KY_CHOI_TIEP, new Uint8Array(0));
  }

  requestRoomList(input: {
    moneyType?: number;
    maxUserPerRoom?: number;
    moneyBet?: number;
    rule?: number;
    from?: number;
    to?: number;
  }): void {
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

  private openSocket(): void {
    this.state.socket = this.state.reconnectAttempts > 0 ? "reconnecting" : "connecting";
    this.state.login = "idle";
    this.state.joined = false;

    try {
      this.socket = new WebSocket(this.options.wsUrl);
      this.socket.binaryType = "arraybuffer";

      this.socket.addEventListener("open", () => {
        const wasReconnecting = this.state.reconnectAttempts > 0;

        this.state.socket = "open";
        this.options.handlers?.onOpen?.();

        if (wasReconnecting) {
          this.options.handlers?.onReconnectSuccess?.();
        }

        this.state.reconnectAttempts = 0;
        this.sendCoreLogin();
      });

      this.socket.addEventListener("message", (event) => {
        this.handleMessage(event).catch((cause) => {
          this.emitError(new BacayClientError("PACKET_DECODE_ERROR", "Failed to decode incoming packet", cause));
        });
      });

      this.socket.addEventListener("close", (event) => {
        this.state.socket = "closed";
        this.state.joined = false;
        this.options.handlers?.onClose?.(event);

        if (!this.manualClose) {
          this.scheduleReconnect();
        }
      });

      this.socket.addEventListener("error", () => {
        this.emitError(new BacayClientError("UNKNOWN_ERROR", "WebSocket error"));
      });
    } catch (cause) {
      this.emitError(new BacayClientError("UNKNOWN_ERROR", "Failed to open WebSocket", cause));
      this.scheduleReconnect();
    }
  }

  private async handleMessage(event: MessageEvent): Promise<void> {
    const bytes = await normalizeIncomingBytes(event.data);
    if (!bytes) return;

    const packet = decodeServerPacket(bytes);
    this.options.handlers?.onRawMessage?.(packet);
    this.handlePacket(packet);
  }

  private sendCoreLogin(): void {
    this.ensureOpenSocket();
    this.state.login = "login-sent";

    const body = concatBytes(
      encodeBzString(this.options.nickname),
      encodeBzString(this.options.sessionKey)
    );

    this.sendPacket(1, BacayCmd.LOGIN, body);
  }

  private joinRoom(): void {
    this.ensureOpenSocket();

    const joinConfig = this.options.joinConfig;

    if (!joinConfig || joinConfig.mode === "by-bet") {
      const body = concatBytes(
        encodeInt32(joinConfig?.moneyType || 0),
        encodeInt32(joinConfig?.maxUserPerRoom || 8),
        encodeInt64(joinConfig?.moneyBet || 1000),
        encodeInt32(joinConfig?.rule || 0)
      );

      this.sendPacket(1, BacayCmd.JOIN_BY_BET, body);
      return;
    }

    const body = concatBytes(
      encodeInt32(joinConfig.roomId),
      encodeBzString(joinConfig.password || "")
    );

    this.sendPacket(1, BacayCmd.JOIN_BY_ROOM_ID, body);
  }

  private handlePacket(packet: BacayPacket): void {
    const cmd = packet.cmd;

    if (cmd === BacayCmd.LOGIN) {
      // Confirm this loginCode index with your actual protocol.
      const loginCode = packet.rawBytes[3];

      if (loginCode === 0) {
        this.state.login = "login-ok";
        this.options.handlers?.onLoginSuccess?.(packet);
        this.joinRoom();
      } else {
        this.state.login = "login-fail";

        const error = new BacayClientError(
          "LOGIN_FAILED",
          `Socket login failed with code=${loginCode}`
        );

        this.options.handlers?.onLoginError?.(error, packet);
        this.emitError(error);
      }

      return;
    }

    if (cmd === BacayCmd.JOIN_ROOM_SUCCESS) {
      this.state.joined = true;
      this.options.handlers?.onJoinSuccess?.(packet);
      return;
    }

    if (cmd === BacayCmd.JOIN_BY_BET || cmd === BacayCmd.JOIN_BY_ROOM_ID) {
      const joinFailCode = packet.rawBytes[3] ?? -1;

      if (joinFailCode !== 0) {
        const joinFailReason = this.getJoinFailReason(joinFailCode);
        const error = new BacayClientError(
          "JOIN_FAILED",
          `Join room failed with code=${joinFailCode} (${joinFailReason})`
        );

        this.options.handlers?.onJoinError?.(
          error,
          { joinFailCode, joinFailReason },
          packet
        );
        this.emitError(error);
      }

      return;
    }

    if (cmd === BacayCmd.THONG_TIN_BAN_CHOI) {
      this.options.handlers?.onReconnectInfo?.(packet);
      return;
    }

    if (cmd === BacayCmd.KET_THUC) {
      this.options.handlers?.onEndGame?.(packet);
      return;
    }

    if (cmd === BacayCmd.CMD_SEND_UPDATE_MATCH) {
      this.options.handlers?.onUpdateMatch?.(packet);
      return;
    }

    if (cmd !== null && cmd >= 3101 && cmd <= 3123) {
      this.options.handlers?.onGameMessage?.(packet);
    }
  }

  private sendPacket(controllerId: number, actionId: number, body: Uint8Array): void {
    this.ensureOpenSocket();

    const packet = encodeWsPacket(controllerId, actionId, body);
    this.socket?.send(packet.buffer);
  }

  private scheduleReconnect(): void {
    if (!this.reconnectConfig.enabled) return;

    if (this.state.reconnectAttempts >= this.reconnectConfig.maxAttempts) {
      const error = new BacayClientError(
        "MAX_RECONNECT_ATTEMPTS",
        `Reconnect failed after ${this.reconnectConfig.maxAttempts} attempts`
      );

      this.options.handlers?.onReconnectFailed?.(error);
      this.emitError(error);
      return;
    }

    this.state.reconnectAttempts += 1;

    const delayMs = Math.min(
      this.reconnectConfig.baseDelayMs * Math.pow(2, this.state.reconnectAttempts - 1),
      this.reconnectConfig.maxDelayMs
    );

    this.options.handlers?.onReconnectStart?.(this.state.reconnectAttempts, delayMs);

    this.clearReconnectTimer();
    this.reconnectTimer = setTimeout(() => {
      this.openSocket();
    }, delayMs);
  }

  private clearReconnectTimer(): void {
    if (this.reconnectTimer) {
      clearTimeout(this.reconnectTimer);
      this.reconnectTimer = null;
    }
  }

  private ensureOpenSocket(): void {
    if (!this.socket || this.socket.readyState !== WebSocket.OPEN) {
      throw new BacayClientError("SOCKET_NOT_OPEN", "Socket is not open");
    }
  }

  private ensureJoined(): void {
    this.ensureOpenSocket();

    if (!this.state.joined) {
      throw new BacayClientError(
        "NOT_JOINED_ROOM",
        "You must wait for 3118 JOIN_ROOM_SUCCESS before sending Bacay commands"
      );
    }
  }

  private validateConfig(): void {
    if (!this.options.wsUrl) {
      throw new BacayClientError("MISSING_CONFIG", "Missing wsUrl");
    }

    if (!this.options.nickname) {
      throw new BacayClientError("MISSING_CONFIG", "Missing nickname");
    }

    if (!this.options.sessionKey) {
      throw new BacayClientError("MISSING_CONFIG", "Missing sessionKey");
    }
  }

  private emitError(error: BacayClientError): void {
    this.options.handlers?.onError?.(error);
  }

  private getJoinFailReason(joinFailCode: number): JoinFailReason {
    return JOIN_FAIL_CODE_MAP[joinFailCode as JoinFailCode] || "UNKNOWN_JOIN_ERROR";
  }
}
