# JFrog Authentication

**Primary:** JFrog CLI **2.100.0+** with **`jf config`** and **`jf api`** — see [../../../platform-features/skills/jfrog-cli/jf-api-patterns.md](../../../platform-features/skills/jfrog-cli/jf-api-patterns.md).

**Fallback:** `curl` with `$JFROG_URL` and bearer token when the CLI is unavailable. Do not use Python or other HTTP clients for these examples.

## Required Tools

Before proceeding, verify these tools are installed:

```bash
# Check required tools
for tool in curl jq; do
  if ! command -v $tool &> /dev/null; then
    echo "ERROR: $tool is not installed"
  else
    echo "OK: $tool is installed"
  fi
done
```

**Installation if missing:**

| Tool | macOS | Ubuntu/Debian |
|------|-------|---------------|
| curl | `brew install curl` | `sudo apt-get install curl` |
| jq | `brew install jq` | `sudo apt-get install jq` |

## Config File Location

Credentials are stored at the **repository level** in `.env`:

```
{repo-root}/.env
```
see .env.example as reference

**Important**: Add `.env` to your `.gitignore` to avoid committing credentials.

**Important**: Only access tokens are supported. Username/password authentication is NOT supported because the JFrog Access API (used for project creation) requires bearer token authentication.

## Authentication Flow

### 1. Check for Existing Credentials

```bash
# Check if .env file exists and read it
if [ -f .env ]; then
  JFROG_URL=$(grep '^JFROG_URL=' .env | cut -d '=' -f 2-)
  JFROG_TOKEN=$(grep '^JFROG_TOKEN=' .env | cut -d '=' -f 2-)

  if [ -n "$JFROG_URL" ] && [ -n "$JFROG_TOKEN" ]; then
    echo "✓ Loaded credentials from .env"
  else
    echo "✗ .env found but missing JFROG_URL or JFROG_TOKEN"
  fi
else
  echo "✗ No .env file found"
fi
```

### 1b. Confirm Use of Existing Credentials

If credentials are found, **ask the user to confirm** before using them:

> **Existing JFrog configuration found:**
> 
> - **URL**: `{JFROG_URL}`
> - **Token**: `****...****` (stored in `.env`)
> 
> Would you like to **use** these credentials or **change** them?

**Wait for user response:**
- If **"use"**: Validate existing credentials and proceed
- If **"change"**: ask the user to set the right valuers inside .env file, create the file for him if missing

### 2. Prompt for Missing Credentials

If `.env` doesn't exist or is missing required fields, **interactively ask the user** through the chat:

> I need to connect to your JFrog Platform. Please set JFROG_URL and JFROG_TOKEN valuers inside .env file, create the file for him if missing

> You can generate an access token from: `https://your-platform.jfrog.io/ui/admin/configuration/security/access_tokens`

**Ask the customer if values have been set and can be checked** before proceeding. 

When the user answers yes, proceed


### 3. Validate the Token

Token validation requires two checks:
1. **Authentication check** - Verify the token is valid
2. **Platform AppTrust check** - Verify the platform has AppTrust

#### Step 3a: Validate Authentication

First, verify the token works by calling an authenticated endpoint:

```bash
# Validate token - this endpoint requires authentication
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" \
  -H "Authorization: Bearer ${JFROG_TOKEN}" \
  "${JFROG_URL}/artifactory/api/system/ping")

if [ "$HTTP_CODE" = "200" ]; then
  echo "✓ Token authentication successful"
else
  echo "✗ Token authentication failed: HTTP ${HTTP_CODE}"
fi
```

**If authentication fails** (HTTP 401 or 403):
> The provided token is invalid. Please check:
> 1. The token is correctly copied (no extra spaces)
> 2. The JFrog URL is correct
> 3. The token has not expired

#### Step 3b: Validate AppTrust is included in the platform subscription

After authentication succeeds, verify the platform subscription includes   **AppTrust**:

```bash
# Check platform includes AppTrust - this endpoint queries AppTrust entitlement
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" \
  -H "Authorization: Bearer ${JFROG_TOKEN}" \
  "${JFROG_URL}/apptrust/api/v1/applications")

if [ "$HTTP_CODE" = "200" ]; then
  echo "✓ Platform AppTrust existance confirmed"
else
  echo "✗ Platform AppTrust existance failed: HTTP ${HTTP_CODE}"
fi
```

**If platform apptrust check fails with 404** (404):
> The provided platform does not have **AppTrust** entitlement.
> 
> This skill requires a platform to:
> - Create templates
> - Create rules
> - Create policies
> 
> Please provide a platform with AppTrust for usign this skill.

**If platform apptrust check fails with 403 or 401** (403, 401):
> The provided access token does not have **AppTrust** priveledges.
> 
> This permission is required for:
> - Create templates
> - Create rules
> - Create policies
> 
> Please provide an access token with policies management privileges.
> You can generate one from: `{jfrog-url}/ui/admin/configuration/security/access_tokens`

**Only proceed if BOTH checks pass.**

## Health Check (Optional)

To check if the JFrog Platform is accessible (before authentication):

```bash
# Unauthenticated health check
curl -s "${JFROG_URL}/artifactory/api/v1/system/readiness"
```

**Expected response**:
```json
{
  "status": "OK"
}
```

Use this to distinguish between:
- Platform unreachable (network issue)
- Platform reachable but token invalid (auth issue)

## Using Credentials in curl Commands

Once credentials are loaded, use them in API calls:

```bash
# Load credentials from .env config
JFROG_URL=$(grep '^JFROG_URL=' .env | cut -d '=' -f 2-)
JFROG_TOKEN=$(grep '^JFROG_TOKEN=' .env | cut -d '=' -f 2-)


# Make authenticated API call
curl -X POST "${JFROG_URL}/unifiedpolicy/api/v1/templates" \
  -H "Authorization: Bearer ${JFROG_TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{"description": "test template", "name": "test Template", "category": "workflow", "parameters": [],"rego": "package curation.policies\n\nimport rego.v1\n\nallow := {\n    \"should_allow\": true,\n}", "scanners": "noop"],"version": "1.0.0","data_source_type": "noop","is_custom": true}'
```

## Security Notes

1. **Never log or display the token** - mask it in any output
2. **.env file permissions** - must be `600` (owner read/write only)
3. **Don't commit credentials** - add `.env` to `.gitignore`

## Future: User-Level Configuration

Currently, all configuration is at the project level (`.env`). In a future update, we will add support for user-level configuration at `~/.jfrog/.env` with the following precedence:

1. Project-level `.env` (highest priority)
2. User-level `~/.jfrog/env` (fallback)

This will allow users to set a default JFrog configuration while still allowing project-specific overrides.

## Troubleshooting

| Issue | Solution |
|-------|----------|
| "Permission denied" reading config | Check file permissions: `ls -la .jfrog/config` |
| "No such file" | Run from repo root, or config not created yet |
| "Connection refused" | Check URL is correct and platform is running |
| "401 Unauthorized" | Token is invalid or expired, regenerate it |
| "403 Forbidden" | Token doesn't have policy mannagement privileges |
| "404 page not found" | Platform doesn't have AppTrust entitlement |
| "jq: command not found" | Install jq: `brew install jq` (macOS) |
| Config committed to git | Add `.jfrog/` to `.gitignore` and remove from history |