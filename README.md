Copy this file as `check_ports.sh`:

```bash
#!/usr/bin/env bash

HOST="${HOST:-43.207.3.134}"
TIMEOUT="${TIMEOUT:-2}"

echo "Checking internet-facing ports on ${HOST} by .env.example standard (timeout=${TIMEOUT}s)"

check_port() {
  local name="$1"
  local type="$2"
  local port="$3"

  if nc -z -w "$TIMEOUT" "$HOST" "$port" >/dev/null 2>&1; then
    printf "[OK]   %-15s %-12s %s:%s\n" "$name" "$type" "$HOST" "$port"
  else
    printf "[FAIL] %-15s %-12s %s:%s\n" "$name" "$type" "$HOST" "$port"
  fi
}

check_port "VinPlayPortal"  "http"   8081
check_port "VinPlayPortal"  "https"  8443
check_port "WsPay"          "http"   18081
check_port "WsPay"          "https"  8643
check_port "VinPlayBackend" "app"    8082

check_port "Bacay"          "game"   21043

check_port "Baicao"         "game"   21143
check_port "Baicao"         "ws"     21144
check_port "Baicao"         "http"   12080

check_port "BanCa"          "game"   21243
check_port "BanCa"          "ws"     21244
check_port "BanCa"          "wss"    21246

check_port "Binh"           "game"   21343
check_port "Binh"           "ws"     21344
check_port "Binh"           "wss"    21346

check_port "Caro"           "game"   21443
check_port "Caro"           "ws"     21444
check_port "Caro"           "wss"    21446

check_port "Coup"           "game"   21543
check_port "Coup"           "ws"     21544
check_port "Coup"           "wss"    21546

check_port "Lieng"          "game"   21643
check_port "Lieng"          "ws"     21644
check_port "Lieng"          "wss"    21646

check_port "minigame"       "game"   22343
check_port "minigame"       "ws"     22344

check_port "Poker"          "game"   21743
check_port "Poker"          "ws"     21744
check_port "Poker"          "wss"    21746

check_port "PokerTour"      "game"   21843

check_port "Sam"            "game"   21943
check_port "Sam"            "ws"     21944
check_port "Sam"            "wss"    21946

check_port "SlotMachine"    "game"   22043
check_port "SlotMachine"    "ws"     22044
check_port "SlotMachine"    "wss"    22046

check_port "Tienlen"        "game"   22143
check_port "Tienlen"        "ws"     22144
check_port "Tienlen"        "wss"    22146

check_port "Xizach"         "game"   22243
check_port "Xizach"         "ws"     22244
check_port "Xizach"         "wss"    22246

check_port "xocdia"         "game"   22443
check_port "xocdia"         "ws"     22444
check_port "xocdia"         "wss"    22446
```

Run:

```bash
chmod +x check_ports.sh
./check_ports.sh
```

Change the IP or timeout if needed:

```bash
HOST=43.207.3.134 TIMEOUT=2 ./check_ports.sh
```
