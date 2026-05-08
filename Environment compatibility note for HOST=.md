Environment compatibility note for HOST=127.0.0.1

Target host:
- http://127.0.0.1:8081/api/v2

Observed behavior on this host is NOT fully aligned with the official VinPlay API v2 guide.
When testing against HOST=127.0.0.1, the automation must apply the following compatibility rules.

1. Auth credential mismatch
Official spec credentials:
- operatorCode = OP001
- apiKey = api_key_op001_live_prod2025
- secretKey = test-secret-key-12345

Behavior on HOST=127.0.0.1:
- Using official credentials on POST /api/v2/4001 returns:
  errorCode = 1001
  errorMessage = "Invalid operator code or API key"

Working legacy credentials on HOST=127.0.0.1:
- operatorCode = default
- apiKey = default_secret_key
- secretKey = default_secret_key

Required AI behavior:
- If host is 127.0.0.1, prefer legacy credentials above.
- Do not assume official credentials are valid on this host.
- If official credentials fail with 1001 on this host, retry using legacy credentials.

2. Token scope mismatch
Official spec expected token scope:
- game:read,game:write,balance:read,transfer:write

Behavior on HOST=127.0.0.1:
- POST /api/v2/4001 succeeds with legacy credentials but returns scope:
  "read,write"

Required AI behavior:
- Do not hard-fail if token scope is "read,write" on HOST=127.0.0.1.
- Treat this as a host-specific legacy/auth-version difference.
- Log a warning instead of failing the flow.

3. Create account endpoint 4011 mismatch
Official spec expectation:
- POST /api/v2/4011 should create account successfully.
- Expected response includes username, currency, balance=0, status=ACTIVE.

Behavior on HOST=127.0.0.1:
- After successful auth, POST /api/v2/4011 fails with:
  errorCode = 5000
  errorMessage = "An unexpected error occurred"

This happens for all tested payload variants:
- minimal body:
  {"operatorCode":"default","username":"..."}
- with currency:
  {"operatorCode":"default","username":"...","currency":"VND"}
- full optional fields:
  {"operatorCode":"default","username":"...","currency":"VND","country":"VN","language":"vi"}

Required AI behavior:
- Treat 4011 failure on HOST=127.0.0.1 as backend/environment incompatibility, not as a client payload bug.
- Do not keep mutating the request body endlessly trying to fix it.
- Report that this host cannot complete the official v2 flow because create-player is broken server-side.
- Mark the flow as blocked at 4011.

4. Endpoint availability after auth
Observed behavior on HOST=127.0.0.1:
- POST /api/v2/4012 with nonexistent username returns:
  errorCode = 3001
  errorMessage = "Player account does not exist"
- POST /api/v2/4021 with nonexistent username returns 3001
- POST /api/v2/4031 with nonexistent username returns 3001

Required AI behavior:
- Interpret this as evidence that the v2 routes exist and auth works with legacy credentials.
- The main blocker is specifically create-account 4011, not general connectivity.

5. History/query endpoint behavior mismatch
Observed behavior on HOST=127.0.0.1:
- POST /api/v2/4042 for missing transaction returns success=true with data=[]
- POST /api/v2/4041 for arbitrary ticket returns success=true with data=[]

Required AI behavior:
- Do not assume empty arrays are client-side parsing errors.
- Treat empty history responses on this host as acceptable host-specific behavior unless the official environment is required.

6. Decision rule for automated testing
If BASE/HOST points to 127.0.0.1:
- Use legacy auth profile:
  operatorCode=default
  apiKey=default_secret_key
  secretKey=default_secret_key
- Accept token scope "read,write"
- Attempt 4011 once with normal payload
- If 4011 returns 5000, stop the official full-flow test and report:
  "HOST=127.0.0.1 is environment-divergent from the official v2 spec; auth works only with legacy credentials and create-account 4011 is broken server-side."

7. Suggested environment profiles
Profile official:
- BASE=https://s81.tevigames.com/api/v2
- operatorCode=OP001
- apiKey=api_key_op001_live_prod2025
- secretKey=test-secret-key-12345

Profile legacy43:
- BASE=http://127.0.0.1:8081/api/v2
- operatorCode=default
- apiKey=default_secret_key
- secretKey=default_secret_key

Summary:
- HOST=127.0.0.1 should be treated as a legacy/divergent environment.
- It is not safe to enforce the official v2 spec strictly on this host.
- Auto-fix behavior should switch credentials, downgrade some assertions to warnings, and stop at 4011 if server returns 5000.
