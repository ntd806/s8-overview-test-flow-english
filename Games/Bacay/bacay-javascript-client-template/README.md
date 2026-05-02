# Bacay Frontend Integration Guide

## Overview
This package provides a simple, developer-friendly template to integrate the Bacay game via WebSocket.

## Flow
HTTP Login → WebSocket → Core Login → Join Room → Game Flow

## Quick Start

```js
import { BacayFrontendClient } from './client.js';

const client = new BacayFrontendClient({
  wsUrl: "ws://127.0.0.1:21044/websocket",
  nickname: "your_nickname",
  sessionKey: "your_session_key",
});

client.connect();
```

## Events

| Event | Description |
|------|------------|
| onLoginSuccess | Login successful |
| onJoinSuccess | Received 3118 |
| onGameMessage | Game message received |

## Notes
- Wait for 3118 before sending game commands
- Login must succeed before joining room
