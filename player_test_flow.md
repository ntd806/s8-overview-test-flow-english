# How to Run `player_test_flow-v1.sh`

This file describes the current flow of the script [player_test_flow-v1.sh](/Users/anthonynguyen/Downloads/ProjectsS8/winall_svn/s8-backend/player_test_flow-v1.sh).

## 1. Goal

This script is used to test the Portal v1 flow:

```text
Get captcha
Register a new user
Login
Set nickname if the user does not have one yet
Get sessionKey
Get game config
```

The final values you need are:

```text
USERNAME
PASSWORD
NICKNAME
SESSIONKEY
```

Then use `NICKNAME + SESSIONKEY` to log in to the game socket.

## 2. Requirements Before Running

Make sure Portal v1 is running at:

```text
http://127.0.0.1:8081/api
```

Quick check:

```bash
curl -s 'http://127.0.0.1:8081/api?c=124'
```

If the JSON response contains `id` and `img`, Portal is running correctly.

## 3. Grant Permission and Run the Script

```bash
chmod +x /Users/anthonynguyen/Downloads/ProjectsS8/winall_svn/s8-backend/player_test_flow-v1.sh
cd /Users/anthonynguyen/Downloads/ProjectsS8/winall_svn/s8-backend
./player_test_flow-v1.sh
```

## 4. How the Script Generates Test Data

In most cases, you do not need to edit the top of the file manually.

It auto-generates:

```text
USERNAME = test + last 7 digits of the timestamp
PASSWORD = 123456
NICKNAME = play_ + last 7 digits of the timestamp
```

Example:

```text
USERNAME = test4812184
PASSWORD = 123456
NICKNAME = play_4812184
```

Current constraints followed by the script:

```text
USERNAME contains only letters and numbers, length 6-16
NICKNAME contains letters, numbers, and _, length 6-16
```

## 5. Actual Runtime Flow

### Step 1: Get captcha

The script calls:

```bash
curl -s 'http://127.0.0.1:8081/api?c=124'
```

Then it:

```text
Saves the image as captcha.png
Opens captcha.png
Prompts you to enter the 3-character captcha
```

### Step 2: Register

The script calls:

```bash
curl -s "http://127.0.0.1:8081/api?c=1&un=$USERNAME&pw=$PASSWORD&cp=$CAPTCHA&cid=$CID"
```

Common outcomes:

```text
errorCode = 0     -> registration succeeded
errorCode = 1006  -> user already exists, the script still continues to login
errorCode = 115   -> wrong captcha
errorCode = 101   -> invalid username
```

### Step 3: Login

The script calls:

```bash
curl -s "http://127.0.0.1:8081/api?c=3&un=$USERNAME&pw=$PASSWORD"
```

Branches handled by the script:

```text
success = true + sessionKey exists -> login succeeded
errorCode = 2001                   -> user has no nickname yet, continue to set nickname
errorCode = 1001                   -> script retries login with MD5 password
```

If plain-password login returns `1001`, the script will try:

```bash
pw=MD5(123456)
```

If MD5 login still fails, the script stops.

### Step 4: Set nickname if missing

When login returns `2001`, the script calls:

```bash
curl -s "http://127.0.0.1:8081/api?c=5&un=$USERNAME&pw=$LOGIN_PASSWORD&nn=$NICKNAME"
```

Branches handled by the script:

```text
success = true + sessionKey exists -> success
errorCode = 106                    -> invalid nickname, the script shortens the nickname and retries
errorCode = 1013                   -> nickname already exists, the script logs in again to get sessionKey
```

Fallback nickname when `106` happens:

```text
p + last 7 digits of the timestamp
```

Example:

```text
p4812184
```

### Step 5: Get game config

The script calls:

```bash
curl -s 'http://127.0.0.1:8081/api?c=6&v=1&pf=web&did=test&vnt='
```

Purpose:

```text
See which host/port each game is published on
```

### Step 6: Print the final result

The script prints:

```text
USERNAME
PASSWORD
NICKNAME
SESSIONKEY
```

## 6. How to Read the Result Correctly

### Typical case

```text
STEP 2 register -> errorCode 0
STEP 3 login    -> errorCode 2001
STEP 4 set nick -> errorCode 0
FINAL RESULT    -> SESSIONKEY exists
```

Or:

```text
STEP 2 register -> errorCode 1006
STEP 3 login    -> success true
FINAL RESULT    -> SESSIONKEY exists
```

## 7. Common Errors

### `115`

Wrong captcha.

How to handle it:

```text
Run the script again
Enter the new 3-character captcha correctly
```

### `101`

Invalid username.

The script currently auto-generates a valid username. If you still get this error, it usually means you overrode the `USERNAME` environment variable with an invalid value.

Test again without passing a custom `USERNAME`.

### `2001`

User has no nickname yet.

This is a normal state right after successful registration.

The script will automatically move to the set-nickname step.

### `106`

Invalid nickname.

The current script already includes a retry branch with a shorter nickname.

If it still happens, it is usually because you passed a custom `NICKNAME` that is too long or does not match the expected pattern.

### `1013`

Nickname already exists.

The script will try to log in again to get `sessionKey`.

### `1001`

Login error.

The script will retry with the MD5 password.

If it still fails, the local procedure or local data is usually out of sync.

### `1005`

The user does not exist, or Portal is reading the current data state incorrectly.

With the new local flow, this error should not appear for a user that just registered successfully.

## 8. How to Use the Result to Enter the Game

After the script finishes, take:

```text
NICKNAME
SESSIONKEY
```

Example Bacay game:

```text
ws://127.0.0.1:21044
```

Use:

```text
nickname = the NICKNAME value printed at the end of the script
sessionKey = the SESSIONKEY value printed at the end of the script
```

## 9. Important Note

This script follows the legacy Portal v1 flow:

```text
c=124 -> captcha
c=1   -> register
c=3   -> login
c=5   -> set nickname
c=6   -> get config
```

This file only describes the current flow of `player_test_flow-v1.sh`. It does not describe the v2 flow.
