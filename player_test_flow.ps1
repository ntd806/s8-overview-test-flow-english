# =========================
# CONFIG
# =========================

$PORTAL_URL    = $env:PORTAL_URL
$PORTAL_HOST   = $env:PORTAL_HOST
$APP_HOST      = $env:HOST
$IP            = $env:IP
$PORTAL_PORT   = $env:PORTAL_PORT
$PORTAL_SCHEME = $env:PORTAL_SCHEME

if (-not $PORTAL_HOST)   { $PORTAL_HOST = "43.207.3.134" }
if (-not $PORTAL_PORT)   { $PORTAL_PORT = "8081" }
if (-not $PORTAL_SCHEME) { $PORTAL_SCHEME = "http" }

if (-not $PORTAL_URL) {
    $PORTAL_URL = "${PORTAL_SCHEME}://${PORTAL_HOST}:${PORTAL_PORT}/api"
}

Write-Host "PORTAL_URL = $PORTAL_URL"

# =========================
# DATA GEN
# =========================

$RUN_SUFFIX   = [int][double]::Parse((Get-Date -UFormat %s))
$SHORT_SUFFIX = $RUN_SUFFIX.ToString().Substring($RUN_SUFFIX.ToString().Length - 6)

$USERNAME = "test$SHORT_SUFFIX"
$PASSWORD = "123456"
$NICKNAME = "play_$SHORT_SUFFIX"

# =========================
# HELPERS
# =========================

function Md5-Text($text) {
    $md5 = [System.Security.Cryptography.MD5]::Create()
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($text)
    $hash = $md5.ComputeHash($bytes)
    return ($hash | ForEach-Object { $_.ToString("x2") }) -join ""
}

function Enc($text) {
    return [System.Net.WebUtility]::UrlEncode($text)
}

function Request-Json($url, $stepName) {
    Write-Host ""
    Write-Host "REQUEST [$stepName]:"
    Write-Host $url

    try {
        $res = Invoke-WebRequest `
            -Uri $url `
            -UseBasicParsing `
            -TimeoutSec 20 `
            -ErrorAction Stop

        Write-Host "STATUS [$stepName]: $($res.StatusCode)"
        Write-Host "BODY [$stepName]:"
        Write-Host $res.Content

        if ([string]::IsNullOrWhiteSpace($res.Content)) {
            Write-Host "ERROR [$stepName]: empty response"
            exit 1
        }

        return ($res.Content | ConvertFrom-Json)
    }
    catch {
        Write-Host "ERROR [$stepName]: request failed"
        Write-Host $_.Exception.Message

        if ($_.Exception.Response) {
            try {
                $reader = New-Object System.IO.StreamReader($_.Exception.Response.GetResponseStream())
                $body = $reader.ReadToEnd()
                Write-Host "ERROR RESPONSE BODY:"
                Write-Host $body
            } catch {}
        }

        exit 1
    }
}

# =========================
# STEP 1: CAPTCHA
# =========================

Write-Host "=============================="
Write-Host "STEP 1: Get captcha"
Write-Host "=============================="

$captchaUrl  = "${PORTAL_URL}?c=124"
$captchaJson = Request-Json $captchaUrl "captcha"

$CID = $captchaJson.id
$IMG = $captchaJson.img

if (-not $CID) {
    Write-Host "ERROR: cannot get captcha id"
    exit 1
}

if (-not $IMG) {
    Write-Host "ERROR: cannot get captcha image"
    exit 1
}

if ($IMG -like "data:image*base64,*") {
    $IMG = $IMG.Split(",")[1]
}

[System.IO.File]::WriteAllBytes("captcha.png", [Convert]::FromBase64String($IMG))

Write-Host "Captcha ID: $CID"
Write-Host "Saved captcha image: captcha.png"

Start-Process "captcha.png"

$CAPTCHA = Read-Host "Enter captcha"

if (-not $CAPTCHA) {
    Write-Host "ERROR: captcha empty"
    exit 1
}

# =========================
# STEP 2: REGISTER
# =========================

Write-Host "=============================="
Write-Host "STEP 2: Register"
Write-Host "=============================="

$registerUrl = "${PORTAL_URL}?c=1&un=$(Enc $USERNAME)&pw=$(Enc $PASSWORD)&cp=$(Enc $CAPTCHA)&cid=$(Enc $CID)"
$registerJson = Request-Json $registerUrl "register"

if (($registerJson.success -ne $true) -and ($registerJson.errorCode -ne 1006)) {
    Write-Host "ERROR: register failed"
    Write-Host "USERNAME = $USERNAME"
    Write-Host "ERROR CODE = $($registerJson.errorCode)"
    Write-Host "MESSAGE = $($registerJson.message)"
    exit 1
}

# =========================
# STEP 3: LOGIN
# =========================

Write-Host "=============================="
Write-Host "STEP 3: Login"
Write-Host "=============================="

$loginUrl = "${PORTAL_URL}?c=3&un=$(Enc $USERNAME)&pw=$(Enc $PASSWORD)"
$loginJson = Request-Json $loginUrl "login"

$SESSION_KEY = $loginJson.sessionKey

# fallback MD5
if (-not $SESSION_KEY -and $loginJson.errorCode -eq 1001) {
    Write-Host "Login failed with plain password. Retrying with MD5..."

    $PASSWORD_MD5 = Md5-Text $PASSWORD
    $loginUrl = "${PORTAL_URL}?c=3&un=$(Enc $USERNAME)&pw=$(Enc $PASSWORD_MD5)"
    $loginJson = Request-Json $loginUrl "login-md5"

    $SESSION_KEY = $loginJson.sessionKey
}

# =========================
# STEP 4: NICKNAME
# =========================

Write-Host "=============================="
Write-Host "STEP 4: Set nickname"
Write-Host "=============================="

if (-not $SESSION_KEY) {
    $nickUrl = "${PORTAL_URL}?c=5&un=$(Enc $USERNAME)&pw=$(Enc $PASSWORD)&nn=$(Enc $NICKNAME)"
    $nickJson = Request-Json $nickUrl "nickname"

    $SESSION_KEY = $nickJson.sessionKey
}

if (-not $SESSION_KEY) {
    Write-Host "ERROR: cannot get sessionKey"
    Write-Host "USERNAME = $USERNAME"
    Write-Host "PASSWORD = $PASSWORD"
    exit 1
}

# =========================
# STEP 5: CONFIG
# =========================

Write-Host "=============================="
Write-Host "STEP 5: Get config"
Write-Host "=============================="

$configUrl = "${PORTAL_URL}?c=6&v=1&pf=web&did=test&vnt="
$configJson = Request-Json $configUrl "config"

# =========================
# FINAL
# =========================

Write-Host "=============================="
Write-Host "FINAL RESULT"
Write-Host "=============================="

Write-Host "USERNAME   = $USERNAME"
Write-Host "PASSWORD   = $PASSWORD"
Write-Host "NICKNAME   = $NICKNAME"
Write-Host "SESSIONKEY = $SESSION_KEY"

Write-Host ""
Write-Host "Use nickname + sessionKey to login socket game"
Write-Host "Example: ws://127.0.0.1:21044"