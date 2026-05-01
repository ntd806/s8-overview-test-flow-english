$ErrorActionPreference = "Stop"

# =========================
# CONFIG
# =========================

$INPUT_BASE          = $env:BASE
$INPUT_PORTAL_HOST   = $env:PORTAL_HOST
$INPUT_APP_HOST      = $env:HOST
$INPUT_IP            = $env:IP
$INPUT_PORTAL_PORT   = $env:PORTAL_PORT
$INPUT_PORTAL_SCHEME = $env:PORTAL_SCHEME

$ENV_FILE = if ($env:ENV_FILE) { $env:ENV_FILE } else { ".env" }

if (Test-Path $ENV_FILE) {
    Get-Content $ENV_FILE | ForEach-Object {
        $line = $_.Trim()

        if ($line -and -not $line.StartsWith("#") -and $line.Contains("=")) {
            $parts = $line.Split("=", 2)
            $key = $parts[0].Trim()
            $value = $parts[1].Trim().Trim('"').Trim("'")
            [Environment]::SetEnvironmentVariable($key, $value, "Process")
        }
    }
}

$PORTAL_HOST = if ($INPUT_PORTAL_HOST) {
    $INPUT_PORTAL_HOST
} elseif ($env:PORTAL_HOST) {
    $env:PORTAL_HOST
} elseif ($INPUT_APP_HOST) {
    $INPUT_APP_HOST
} elseif ($env:HOST) {
    $env:HOST
} elseif ($INPUT_IP) {
    $INPUT_IP
} elseif ($env:IP) {
    $env:IP
} else {
    "127.0.0.1"
}

$PORTAL_PORT = if ($INPUT_PORTAL_PORT) {
    $INPUT_PORTAL_PORT
} elseif ($env:PORTAL_PORT) {
    $env:PORTAL_PORT
} else {
    "8081"
}

$PORTAL_SCHEME = if ($INPUT_PORTAL_SCHEME) {
    $INPUT_PORTAL_SCHEME
} elseif ($env:PORTAL_SCHEME) {
    $env:PORTAL_SCHEME
} else {
    "http"
}

$BASE = if ($INPUT_BASE) {
    $INPUT_BASE
} elseif ($env:BASE) {
    $env:BASE
} else {
    "${PORTAL_SCHEME}://${PORTAL_HOST}:${PORTAL_PORT}"
}

$OP       = if ($env:OP) { $env:OP } else { "default" }
$API_KEY  = if ($env:API_KEY) { $env:API_KEY } else { "default_secret_key" }
$SECRET   = if ($env:SECRET) { $env:SECRET } else { "default_secret_key" }
$CURRENCY = if ($env:CURRENCY) { $env:CURRENCY } else { "VND" }
$GAME_ID  = if ($env:GAME_ID) { $env:GAME_ID } else { "bacay" }

$DEPOSIT_AMOUNT  = if ($env:DEPOSIT_AMOUNT) { [int]$env:DEPOSIT_AMOUNT } else { 10000 }
$WITHDRAW_AMOUNT = if ($env:WITHDRAW_AMOUNT) { [int]$env:WITHDRAW_AMOUNT } else { 3000 }

$RUN_SUFFIX = [int][double]::Parse((Get-Date -UFormat %s))
$USER_NAME  = "curlv2_$RUN_SUFFIX"
$TXN        = "txn_$USER_NAME"
$WITHDRAW_TXN = "${TXN}_w"

# =========================
# HELPERS
# =========================

function ConvertTo-Base64HmacSha256 {
    param (
        [string]$Text,
        [string]$Secret
    )

    $hmac = New-Object System.Security.Cryptography.HMACSHA256
    $hmac.Key = [System.Text.Encoding]::UTF8.GetBytes($Secret)

    $bytes = [System.Text.Encoding]::UTF8.GetBytes($Text)
    $hash = $hmac.ComputeHash($bytes)

    return [Convert]::ToBase64String($hash)
}

function Print-Json {
    param ($Object)

    if ($Object -is [string]) {
        Write-Host $Object
    } else {
        Write-Host ($Object | ConvertTo-Json -Depth 20)
    }
}

function Assert-Success {
    param (
        [string]$Step,
        $Json
    )

    if ($null -eq $Json) {
        Write-Host ""
        Write-Host "FAILED at step: $Step"
        Write-Host "Response is null"
        exit 1
    }

    if ($Json.success -ne $true) {
        Write-Host ""
        Write-Host "FAILED at step: $Step"
        Write-Host "Response:"
        Print-Json $Json
        exit 1
    }
}

function Call-Api {
    param (
        [string]$Step,
        [string]$Url,
        [hashtable]$Body,
        [hashtable]$Headers = @{}
    )

    Write-Host ""
    Write-Host "=============================="
    Write-Host $Step
    Write-Host "=============================="

    $jsonBody = $Body | ConvertTo-Json -Depth 20

    Write-Host "URL:"
    Write-Host $Url
    Write-Host "BODY:"
    Write-Host $jsonBody

    try {
        $response = Invoke-WebRequest `
            -Uri $Url `
            -Method POST `
            -Headers $Headers `
            -ContentType "application/json" `
            -Body $jsonBody `
            -UseBasicParsing `
            -TimeoutSec 30 `
            -ErrorAction Stop

        Write-Host "STATUS:"
        Write-Host $response.StatusCode

        Write-Host "RESPONSE:"
        Write-Host $response.Content

        if ([string]::IsNullOrWhiteSpace($response.Content)) {
            Write-Host "ERROR: empty response at step $Step"
            exit 1
        }

        $json = $response.Content | ConvertFrom-Json

        Assert-Success $Step $json

        return $json
    }
    catch {
        Write-Host ""
        Write-Host "REQUEST FAILED at step: $Step"
        Write-Host $_.Exception.Message

        if ($_.Exception.Response) {
            try {
                $reader = New-Object System.IO.StreamReader($_.Exception.Response.GetResponseStream())
                $errorBody = $reader.ReadToEnd()
                Write-Host "ERROR RESPONSE BODY:"
                Write-Host $errorBody
            } catch {}
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
# 1. GET ACCESS TOKEN
# =========================

Write-Host ""
Write-Host "=============================="
Write-Host "1. Get access token"
Write-Host "=============================="

$TS = "$([int64](([DateTimeOffset]::UtcNow).ToUnixTimeMilliseconds()))"
$SIG_TEXT = "${OP}${API_KEY}${TS}"
$SIG = ConvertTo-Base64HmacSha256 -Text $SIG_TEXT -Secret $SECRET

$tokenBody = @{
    operatorCode = $OP
    apiKey       = $API_KEY
    timestamp    = [int64]$TS
    signature    = $SIG
}

$TOKEN_JSON = Call-Api `
    -Step "1. Get access token" `
    -Url "$BASE/api/v2/4001" `
    -Body $tokenBody

$ACCESS_TOKEN  = $TOKEN_JSON.accessToken
$REFRESH_TOKEN = $TOKEN_JSON.refreshToken

if (-not $ACCESS_TOKEN) {
    Write-Host "Cannot extract accessToken"
    exit 1
}

Write-Host "Access token OK"

$AUTH_HEADERS = @{
    Authorization = "Bearer $ACCESS_TOKEN"
}

# =========================
# 2. CREATE ACCOUNT
# =========================

$CREATE_HEADERS = @{
    Authorization  = "Bearer $ACCESS_TOKEN"
    "X-Request-Id" = "create-$USER_NAME"
}

$createBody = @{
    operatorCode = $OP
    username     = $USER_NAME
    currency     = $CURRENCY
}

Call-Api `
    -Step "2. Create account" `
    -Url "$BASE/api/v2/4011" `
    -Body $createBody `
    -Headers $CREATE_HEADERS | Out-Null

# =========================
# 3. CHECK BALANCE
# =========================

$balanceBody = @{
    operatorCode = $OP
    username     = $USER_NAME
}

Call-Api `
    -Step "3. Check balance" `
    -Url "$BASE/api/v2/4012" `
    -Body $balanceBody `
    -Headers $AUTH_HEADERS | Out-Null

# =========================
# 4. DEPOSIT
# =========================

$depositBody = @{
    operatorCode  = $OP
    username      = $USER_NAME
    transactionId = $TXN
    type          = "DEPOSIT"
    amount        = $DEPOSIT_AMOUNT
    currency      = $CURRENCY
}

Call-Api `
    -Step "4. Deposit" `
    -Url "$BASE/api/v2/4021" `
    -Body $depositBody `
    -Headers $AUTH_HEADERS | Out-Null

# =========================
# 5. LAUNCH GAME
# =========================

$launchBody = @{
    operatorCode = $OP
    username     = $USER_NAME
    gameId       = $GAME_ID
    platform     = "WEB"
}

Call-Api `
    -Step "5. Launch game" `
    -Url "$BASE/api/v2/4031" `
    -Body $launchBody `
    -Headers $AUTH_HEADERS | Out-Null

# =========================
# 6. WITHDRAW
# =========================

$withdrawBody = @{
    operatorCode  = $OP
    username      = $USER_NAME
    transactionId = $WITHDRAW_TXN
    type          = "WITHDRAW"
    amount        = $WITHDRAW_AMOUNT
    currency      = $CURRENCY
}

Call-Api `
    -Step "6. Withdraw" `
    -Url "$BASE/api/v2/4021" `
    -Body $withdrawBody `
    -Headers $AUTH_HEADERS | Out-Null

# =========================
# 7. FINAL BALANCE CHECK
# =========================

$FINAL_JSON = Call-Api `
    -Step "7. Final balance" `
    -Url "$BASE/api/v2/4012" `
    -Body $balanceBody `
    -Headers $AUTH_HEADERS

$FINAL_BALANCE = [int]$FINAL_JSON.balance
$EXPECTED_BALANCE = $DEPOSIT_AMOUNT - $WITHDRAW_AMOUNT

Write-Host ""
Write-Host "Expected: $EXPECTED_BALANCE"
Write-Host "Actual:   $FINAL_BALANCE"

if ($FINAL_BALANCE -ne $EXPECTED_BALANCE) {
    Write-Host "Balance mismatch"
    exit 1
}

# =========================
# DONE
# =========================

Write-Host ""
Write-Host "======================================"
Write-Host "FULL FLOW PASSED"
Write-Host "======================================"
Write-Host "USER: $USER_NAME"
Write-Host "FINAL_BALANCE: $FINAL_BALANCE"
Write-Host "======================================"