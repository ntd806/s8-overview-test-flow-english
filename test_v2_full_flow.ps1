$ErrorActionPreference = "Stop"

# =========================
# CONFIG
# =========================

$ENV_FILE = ".env"

if (Test-Path $ENV_FILE) {
    Get-Content $ENV_FILE | ForEach-Object {
        $line = $_.Trim()
        if ($line -and -not $line.StartsWith("#") -and $line -match "=") {
            $key, $value = $line -split "=", 2
            [Environment]::SetEnvironmentVariable($key.Trim(), $value.Trim(), "Process")
        }
    }
}

$PORTAL_HOST = if ($env:PORTAL_HOST) { $env:PORTAL_HOST } elseif ($env:HOST) { $env:HOST } elseif ($env:IP) { $env:IP } else { "127.0.0.1" }
$PORTAL_PORT = if ($env:PORTAL_PORT) { $env:PORTAL_PORT } else { "8081" }
$PORTAL_SCHEME = if ($env:PORTAL_SCHEME) { $env:PORTAL_SCHEME } else { "http" }

$BASE = if ($env:BASE) {
    $env:BASE
} else {
    "${PORTAL_SCHEME}://${PORTAL_HOST}:${PORTAL_PORT}"
}

$OP       = if ($env:OP) { $env:OP } else { "OP001" }
$API_KEY  = if ($env:API_KEY) { $env:API_KEY } else { "api_key_op001_live_prod2025" }
$SECRET   = if ($env:SECRET) { $env:SECRET } else { "test-secret-key-12345" }
$CURRENCY = if ($env:CURRENCY) { $env:CURRENCY } else { "VND" }
$GAME_ID  = if ($env:GAME_ID) { $env:GAME_ID } else { "bacay" }

$DEPOSIT_AMOUNT  = if ($env:DEPOSIT_AMOUNT) { [int]$env:DEPOSIT_AMOUNT } else { 10000 }
$WITHDRAW_AMOUNT = if ($env:WITHDRAW_AMOUNT) { [int]$env:WITHDRAW_AMOUNT } else { 3000 }
$ASYNC_WAIT_SECONDS = if ($env:ASYNC_WAIT_SECONDS) { [int]$env:ASYNC_WAIT_SECONDS } else { 2 }

$RUN_SUFFIX = [int][double]::Parse((Get-Date -UFormat %s))
$USER_NAME  = "curlv2_$RUN_SUFFIX"
$TXN        = "txn_$USER_NAME"
$WITHDRAW_TXN = "${TXN}_w"

# =========================
# HELPERS
# =========================

function HmacSHA256-Base64 {
    param($text, $secret)

    $hmac = New-Object System.Security.Cryptography.HMACSHA256
    $hmac.Key = [System.Text.Encoding]::UTF8.GetBytes($secret)
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($text)
    return [Convert]::ToBase64String($hmac.ComputeHash($bytes))
}

function Print-Json($obj) {
    Write-Host ($obj | ConvertTo-Json -Depth 20)
}

function Call-Api($step, $url, $body, $headers = @{}) {

    Write-Host ""
    Write-Host "=============================="
    Write-Host $step
    Write-Host "=============================="

    $jsonBody = $body | ConvertTo-Json -Depth 10

    Write-Host "URL:"
    Write-Host $url
    Write-Host "BODY:"
    Write-Host $jsonBody

    try {
        $res = Invoke-WebRequest `
            -Uri $url `
            -Method POST `
            -Headers $headers `
            -ContentType "application/json" `
            -Body $jsonBody `
            -UseBasicParsing `
            -TimeoutSec 30

        Write-Host "STATUS:"
        Write-Host $res.StatusCode

        Write-Host "RESPONSE:"
        Write-Host $res.Content

        $json = $res.Content | ConvertFrom-Json

        if ($json.success -ne $true) {
            Write-Host "FAILED:"
            Print-Json $json
            exit 1
        }

        return $json
    }
    catch {
        Write-Host "REQUEST FAILED:"
        Write-Host $_.Exception.Message

        if ($_.Exception.Response) {
            $reader = New-Object System.IO.StreamReader($_.Exception.Response.GetResponseStream())
            Write-Host "ERROR BODY:"
            Write-Host $reader.ReadToEnd()
        }

        exit 1
    }
}

# =========================
# START
# =========================

Write-Host "======================================"
Write-Host " V2 AUTO TEST FLOW - POWERSHELL"
Write-Host "======================================"
Write-Host "BASE: $BASE"
Write-Host "USER: $USER_NAME"
Write-Host "======================================"

# =========================
# 1. GET TOKEN
# =========================

Write-Host ""
Write-Host "=============================="
Write-Host "1. Get access token"
Write-Host "=============================="

$TS = [int64](([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()))
$SIG = HmacSHA256-Base64 "${OP}${API_KEY}${TS}" $SECRET

$tokenBody = @{
    operatorCode = $OP
    apiKey       = $API_KEY
    timestamp    = $TS
    signature    = $SIG
}

$TOKEN_JSON = Call-Api "1. Get access token" "$BASE/api/v2/4001" $tokenBody

# ⭐ FIX QUAN TRỌNG
$ACCESS_TOKEN  = $TOKEN_JSON.data.accessToken
$REFRESH_TOKEN = $TOKEN_JSON.data.refreshToken

if (-not $ACCESS_TOKEN) {
    Write-Host "Cannot extract accessToken"
    Print-Json $TOKEN_JSON
    exit 1
}

Write-Host "Access token OK"

$AUTH_HEADERS = @{
    Authorization = "Bearer $ACCESS_TOKEN"
}

# =========================
# 2. CREATE ACCOUNT
# =========================

Call-Api "2. Create account" "$BASE/api/v2/4011" @{
    operatorCode = $OP
    username     = $USER_NAME
    currency     = $CURRENCY
} @{
    Authorization  = "Bearer $ACCESS_TOKEN"
    "X-Request-Id" = "create-$USER_NAME"
} | Out-Null

# =========================
# 3. CHECK BALANCE
# =========================

Call-Api "3. Check balance" "$BASE/api/v2/4012" @{
    operatorCode = $OP
    username     = $USER_NAME
} $AUTH_HEADERS | Out-Null

# =========================
# 4. DEPOSIT
# =========================

Call-Api "4. Deposit" "$BASE/api/v2/4021" @{
    operatorCode  = $OP
    username      = $USER_NAME
    transactionId = $TXN
    type          = "DEPOSIT"
    amount        = $DEPOSIT_AMOUNT
    currency      = $CURRENCY
} $AUTH_HEADERS | Out-Null

# =========================
# 5. LAUNCH GAME
# =========================

Call-Api "5. Launch game" "$BASE/api/v2/4031" @{
    operatorCode = $OP
    username     = $USER_NAME
    gameId       = $GAME_ID
    platform     = "WEB"
} $AUTH_HEADERS | Out-Null

# =========================
# 6. WITHDRAW
# =========================

Call-Api "6. Withdraw" "$BASE/api/v2/4021" @{
    operatorCode  = $OP
    username      = $USER_NAME
    transactionId = $WITHDRAW_TXN
    type          = "WITHDRAW"
    amount        = $WITHDRAW_AMOUNT
    currency      = $CURRENCY
} $AUTH_HEADERS | Out-Null

# =========================
# 7. FINAL BALANCE
# =========================

$FINAL = Call-Api "7. Final balance" "$BASE/api/v2/4012" @{
    operatorCode = $OP
    username     = $USER_NAME
} $AUTH_HEADERS

$FINAL_BALANCE = [int]$FINAL.data.balance
$EXPECTED = $DEPOSIT_AMOUNT - $WITHDRAW_AMOUNT

Write-Host ""
Write-Host "Expected: $EXPECTED"
Write-Host "Actual:   $FINAL_BALANCE"

if ($FINAL_BALANCE -ne $EXPECTED) {
    Write-Host "Balance mismatch"
    exit 1
}

# =========================
# 8. GET PAYMENT TRANSACTION - DEPOSIT
# =========================

Write-Host ""
Write-Host "Waiting ${ASYNC_WAIT_SECONDS}s for async transaction history..."
Start-Sleep -Seconds $ASYNC_WAIT_SECONDS

$DEPOSIT_HISTORY = Call-Api "8. Get payment transaction (deposit)" "$BASE/api/v2/4042" @{
    operatorCode  = $OP
    transactionId = $TXN
} $AUTH_HEADERS

$DEPOSIT_PAYMENT = @($DEPOSIT_HISTORY.data)[0]

if (-not $DEPOSIT_PAYMENT) {
    Write-Host "4042 deposit returned empty data"
    Print-Json $DEPOSIT_HISTORY
    exit 1
}

if ($DEPOSIT_PAYMENT.type -ne "DEPOSIT" -or [int]$DEPOSIT_PAYMENT.amount -ne $DEPOSIT_AMOUNT -or $DEPOSIT_PAYMENT.status -ne "SUCCESS") {
    Write-Host "4042 deposit mismatch"
    Print-Json $DEPOSIT_PAYMENT
    exit 1
}

# =========================
# 9. GET PAYMENT TRANSACTION - WITHDRAW
# =========================

$WITHDRAW_HISTORY = Call-Api "9. Get payment transaction (withdraw)" "$BASE/api/v2/4042" @{
    operatorCode  = $OP
    transactionId = $WITHDRAW_TXN
} $AUTH_HEADERS

$WITHDRAW_PAYMENT = @($WITHDRAW_HISTORY.data)[0]

if (-not $WITHDRAW_PAYMENT) {
    Write-Host "4042 withdraw returned empty data"
    Print-Json $WITHDRAW_HISTORY
    exit 1
}

if ($WITHDRAW_PAYMENT.type -ne "WITHDRAW" -or [int]$WITHDRAW_PAYMENT.amount -ne $WITHDRAW_AMOUNT -or $WITHDRAW_PAYMENT.status -ne "SUCCESS") {
    Write-Host "4042 withdraw mismatch"
    Print-Json $WITHDRAW_PAYMENT
    exit 1
}

Write-Host ""
Write-Host "======================================"
Write-Host "FULL FLOW PASSED"
Write-Host "======================================"
