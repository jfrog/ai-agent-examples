# Agent-Driven Login Flow (Multi-Environment)

This procedure resolves which JFrog Platform environment to use, authenticates if needed, and persists credentials via `jf config`. The agent executes this flow itself. Requires Artifactory 7.64.0+ and the **JFrog CLI (`jf`) 2.100.0 or newer** (for **`jf api`** and the patterns in [jf-api-patterns.md](jf-api-patterns.md)).

## Security Rules

- **Never print tokens.** Do not `echo`, `cat`, or otherwise display access tokens in terminal output or chat messages. Use commands that extract tokens into variables silently.
- **Never log token values.** When confirming auth status, say "authenticated as user X" or "token is set" -- never show the token itself.
- **`jf config` is the sole credential store.** Never store tokens in files, environment variable profiles, or project directories. The CLI encrypts tokens at rest.
- **Validate URLs.** Before using a user-provided URL, verify it with the ping endpoint. Do not pass unvalidated URLs to shell commands.

## Step 0 -- Ensure `jf` CLI Is Installed

```bash
command -v jf >/dev/null 2>&1 && jf --version
```

If `jf` is not found, install it:

**macOS:**

```bash
brew install jfrog-cli
```

**Linux:**

```bash
curl -fL https://install-cli.jfrog.io | sh
```

Confirm the installation succeeded:

```bash
jf --version
```

**Minimum version 2.100.0** (required for `jf api`):

```bash
VER=$(jf --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
MIN="2.100.0"
if [ -z "$VER" ] || [ "$(printf '%s\n%s' "$MIN" "$VER" | sort -V | tail -1)" != "$VER" ]; then
  echo "ERROR: JFrog CLI must be $MIN or newer (found: ${VER:-none}). Upgrade from the install docs."
  exit 1
fi
```

If installation fails, ask the user to install manually from [Install JFrog CLI](https://docs.jfrog.com/integrations/docs/download-and-install-the-jfrog-cli) (see also [JFrog CLI on jfrog.com](https://jfrog.com/help/r/jfrog-cli/install-the-jfrog-cli)).

## Step 1 -- Resolve the Active Environment

Check for saved credentials. If the user already specified a JFrog URL or domain in their message, match it against saved servers and skip straight to Step 2.

```bash
jf config show 2>/dev/null
```

This lists all configured servers with their IDs and URLs.

- **0 servers configured** -- ask the user for their JFrog Platform URL, then go to [Web Login](#step-3----web-login).
- **1 server configured** -- use it. Run `jf config use <server-id>`, then go to Step 2.
- **2+ servers configured** -- list the server IDs and URLs and ask the user which environment they want to use. Example prompt: "I found these JFrog environments: `mycompany` (mycompany.jfrog.io), `staging` (staging.jfrog.io). Which one should I use?"

To activate a server:

```bash
jf config use <server-id>
```

If no servers are configured, ask the user: "What is your JFrog Platform URL? (e.g. `https://mycompany.jfrog.io`)" -- then proceed to web login.

## Step 1b -- Confirm platform URL (wrong-instance guard)

After the intended server is selected (`jf config use` if needed):

1. Run **`jf config show`** and **list each Server ID and JFrog Platform URL** (or paste the relevant lines into chat).
2. Ask the user **one clear question**: whether this is the correct JFrog instance for the task (or which server id to use if they want to switch). If only one server exists, still show its URL once so they can catch a mismatch with a manifest `jfrog.url` or their intent.
3. If they need a different server, run `jf config use <server-id>` and repeat this step.

## Step 1c -- Readiness check

Only **after** the user confirms the platform in Step 1b:

```bash
BODY=/tmp/jf-readiness.json
CODE=/tmp/jf-readiness.code
jf api /artifactory/api/v1/system/readiness >"$BODY" 2>"$CODE"
HTTP_CODE=$(tr -d '\r\n' < "$CODE")
```

Expect **HTTP 200**. Add **`--server-id=<id>`** if the active default is not the confirmed server. On failure, stop and fix URL/credentials before other API calls.

## Step 2 -- Extract Active Credentials

Once the active environment is resolved (from `jf config` or after web login), **Steps 1b–1c** have succeeded, and readiness passed, extract URL and token into transient shell variables for the current session. These variables support **manifest URL checks**, **`curl` fallback**, and skills that still reference `$JFROG_URL` / `$JFROG_ACCESS_TOKEN`. **Preferred** JFrog REST access is **`jf api`** (see [jf-api-patterns.md](jf-api-patterns.md)) and does not require exporting the token for each call.

**Preferred method** -- reliable extraction via `jf config export`:

```bash
JFROG_SERVER_ID=$(jf config show 2>/dev/null | grep -i 'Server ID' | head -1 | awk '{print $NF}')
JFROG_URL=$(jf config show 2>/dev/null | grep -i 'JFrog Platform URL' | head -1 | awk '{print $NF}' | sed 's|https://||;s|/$||')
JFROG_ACCESS_TOKEN=$(jf config export "$JFROG_SERVER_ID" 2>/dev/null | \
  python3 -c "
import sys, json, base64
raw = sys.stdin.read().strip()
try:
    data = json.loads(raw)
except Exception:
    data = json.loads(base64.b64decode(raw))
print(data.get('accessToken', ''))
")
```

`JFROG_SERVER_ID` captures the active server ID from Step 1. It is used here for `jf config export` and by downstream commands that need an explicit `--server-id` (e.g., `jf apptrust ping`). The `jf config export` approach is more reliable than parsing `jf config show` output, which masks the token.

These variables are transient -- they exist only in the current shell session and are never persisted or exported to child processes.

## Step 2b -- Generate an Admin-Scoped Token (Optional)

Some operations (creating projects, users, lifecycle stages) require admin privileges. If the user's session token lacks scope for these operations, generate an admin-scoped token:

```bash
jf atc --server-id=<server-id> --groups="*" --expiry=3600
```

> **Note:** Use `jf atc` (the current syntax), not the deprecated `jf rt access-token-create`. The generated token inherits the user's permissions -- it does not elevate a non-admin user to admin.

## Step 3 -- Web Login

Run this flow when no valid credentials exist for the target environment. The user only needs to click a link and log in via their browser.

> **SANDBOX NOTE -- permissions required:** Steps 3a+3b and 3d make `curl` calls to the JFrog Platform URL (an external host) and are blocked by the Cursor sandbox by default. Use these permission levels:
>
> - **Steps 3a+3b:** `required_permissions: ["full_network"]` -- only makes `curl` calls, no filesystem writes outside the workspace.
> - **Step 3d:** `required_permissions: ["all"]` -- in addition to `curl`, this step runs `jf config add` which writes credentials to `~/.jfrog/` (**outside the workspace**). Using `full_network` alone silently blocks the filesystem write, the command exits 1 with no output, and the one-time-use session token is consumed -- requiring the entire login flow to restart.

### 3a+3b -- Verify the server is reachable and register a login session

Combine the ping check and session registration into a **single shell command** (both require `full_network`):

```bash
# Run this with required_permissions: ["full_network"]
JFROG_PLATFORM_URL="https://mycompany.jfrog.io"   # substitute actual URL

PING_CODE=$(curl -s -o /dev/null -w "%{http_code}" "${JFROG_PLATFORM_URL}/artifactory/api/system/ping")
if [ "$PING_CODE" != "200" ]; then
  echo "ERROR: Server not reachable (HTTP $PING_CODE). Ask the user to verify the URL."
  exit 1
fi

SESSION_UUID=$(uuidgen | tr '[:upper:]' '[:lower:]')
VERIFY_CODE=${SESSION_UUID: -4}

curl -s -X POST "${JFROG_PLATFORM_URL}/access/api/v2/authentication/jfrog_client_login/request" \
  -H "Content-Type: application/json" \
  -d "{\"session\":\"${SESSION_UUID}\"}"

echo "SESSION_UUID=${SESSION_UUID}"
echo "VERIFY_CODE=${VERIFY_CODE}"
```

The final two `echo` lines print the values so you can copy them as literals into Step 3d. No authentication is required for these calls.

> **Why combined?** Combining ping + session registration avoids a second `full_network` request approval and ensures both values (`SESSION_UUID`, `VERIFY_CODE`) are captured in the same shell output for use in Step 3d.

### 3c -- Show the verification code and login link

> Copy `SESSION_UUID` and `VERIFY_CODE` from the output of step 3a+3b above. You will substitute them as literal strings in step 3d.

Build the login URL. The `jfClientCode` parameter is always `1` (matching the JFrog CLI behavior):

```bash
LOGIN_URL="${JFROG_PLATFORM_URL}/ui/login?jfClientSession=${SESSION_UUID}&jfClientName=JFrog-Skills&jfClientCode=1"
```

Show the verification code **first and prominently**, then the clickable link. Do not open the browser automatically. Example message:

> ## Verification code: `7890`
>
> Open this link to log in, then enter the code above when prompted:
>
> [Log in to mycompany.jfrog.io](https://mycompany.jfrog.io/ui/login?jfClientSession=a1b2c3d4-e5f6-7890-abcd-ef1234567890&jfClientName=JFrog-Skills&jfClientCode=1)
>
> Let me know when you're done.

### 3d -- Retrieve token, save credentials, and verify

**Wait for the user to confirm** they have completed the login. Do not poll automatically.

> **CRITICAL -- Atomicity requirement:** The entire token retrieval, config save, and verification below **MUST execute in a single shell command**. Shell variables do not persist between separate tool calls. If they run separately, the token will be silently lost. The token endpoint is **one-time use** -- once consumed, the session UUID is invalidated and the entire login flow must restart from Step 3b with a new session.

> **Variable passing:** The agent must substitute `JFROG_PLATFORM_URL` and `SESSION_UUID` as **literal strings** at the top of the command (copied from the output of Steps 3a-3c). Do not rely on shell variables set in prior tool calls.

Once the user confirms they have logged in, run this entire block as **one shell command** with `required_permissions: ["all"]`:

```bash
JFROG_PLATFORM_URL="https://mycompany.jfrog.io"   # substitute actual URL
SESSION_UUID="a1b2c3d4-e5f6-7890-abcd-ef1234567890" # substitute actual UUID from Step 3b

JFROG_HOST=$(echo "$JFROG_PLATFORM_URL" | sed 's|https://||' | sed 's|\.jfrog\.io.*||' | sed 's|[./]|-|g')

HTTP_CODE=$(curl -s -o /tmp/jf_login_resp.json -w "%{http_code}" \
  "$JFROG_PLATFORM_URL/access/api/v2/authentication/jfrog_client_login/token/$SESSION_UUID")

if [ "$HTTP_CODE" != "200" ]; then
  echo "ERROR: Token retrieval failed (HTTP $HTTP_CODE). User may not have completed login."
  rm -f /tmp/jf_login_resp.json
  exit 1
fi

ACCESS_TOKEN=$(python3 -c "import json; print(json.load(open('/tmp/jf_login_resp.json')).get('access_token',''))")
rm -f /tmp/jf_login_resp.json

if [ -z "$ACCESS_TOKEN" ]; then
  echo "ERROR: Empty token in response. Re-run from Step 3b."
  exit 1
fi

jf config remove "$JFROG_HOST" --quiet 2>/dev/null || true
jf config add "$JFROG_HOST" \
  --url="$JFROG_PLATFORM_URL" \
  --access-token="$ACCESS_TOKEN" \
  --interactive=false
jf config use "$JFROG_HOST"

export JFROG_URL=$(echo "$JFROG_PLATFORM_URL" | sed 's|https://||;s|/$||')
export JFROG_ACCESS_TOKEN="$ACCESS_TOKEN"

echo "--- Verifying authentication ---"
jf api /artifactory/api/system/version --server-id="$JFROG_HOST"
```

- **HTTP 200** from the token endpoint -- login succeeded; the script continues to save and verify.
- **HTTP 400** -- user has not completed login yet. Ask the user to try again.
- **Verification output** -- the final `jf api` call should return a JSON object with a `version` field on stdout (HTTP status on stderr). If it returns a 401 error, the token was not saved correctly -- fall back to [Manual Token Setup](#fallback-manual-token-setup).

Then run **Step 1b** (confirm platform URL) and **Step 1c** (readiness) for this server before other operations.

The server ID is derived from the hostname: `https://mycompany.jfrog.io` becomes `mycompany`, `https://acme.jfrog.io` becomes `acme`. For self-hosted URLs like `https://artifactory.internal.corp`, the full hostname is slugified: `artifactory-internal-corp`.

Response body from the token endpoint on success:

```json
{
  "access_token": "<JWT>",
  "refresh_token": "<refresh-token>",
  "expires_in": 3600,
  "token_type": "Bearer",
  "scope": "..."
}
```

## Switch Environment Mid-Session

To switch to a different saved environment during a session:

```bash
jf config use <server-id>
```

Then re-run **Step 1b** and **Step 1c** for the new server, and re-extract transient credentials (**Step 2**).

## Fallback: Manual Token Setup

If the web login flow fails (server too old, network restrictions, etc.), ask the user to:

1. Generate a token in the JFrog UI: **Administration > Identity and Access > Access Tokens > Generate Token**
2. Save it via the CLI (the agent runs this -- the user only pastes the token when prompted):

```bash
jf config add <server-id> --url=https://<jfrog-url> --access-token=<token> --interactive=false
```

Never store the token in environment variable profiles, files, or project directories.

## REST API Reference

| Step | Method | Endpoint | Auth Required | Body / Query Params |
|------|--------|----------|---------------|---------------------|
| Ping | GET | `{url}/artifactory/api/system/ping` | No | -- |
| Register session | POST | `{url}/access/api/v2/authentication/jfrog_client_login/request` | No | `{"session":"<uuid>"}` |
| Browser login | GET | `{url}/ui/login?jfClientSession={uuid}&jfClientName=JFrog-Skills&jfClientCode=1` | No | User opens in browser; `jfClientCode` is always `1`. The verification code the user enters is the last 4 characters of the session UUID |
| Poll for token | GET | `{url}/access/api/v2/authentication/jfrog_client_login/token/{uuid}` | No | -- |
