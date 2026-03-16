# JFrog Authentication

This document describes how to handle authentication with the JFrog Platform.
Use `curl` for all REST API calls; do not use Python or other HTTP clients.

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

## Credential Storage

Credentials are stored in a `.env` file at the **repository root**:

```
JFROG_URL=https://mycompany.jfrog.io
JFROG_ACCESS_TOKEN=eyJ...
```

This ensures project isolation -- each repository can have its own JFrog configuration without clashing with other projects.

**Important**: Add `.env` to your `.gitignore` to avoid committing credentials.

**Important**: Only access tokens are supported. Username/password authentication is NOT supported because the JFrog Access API (used for project creation) requires bearer token authentication.

## Authentication Flow

### 1. Load Credentials

```bash
# Load .env if vars are not already set
if [ -z "$JFROG_URL" ] || [ -z "$JFROG_ACCESS_TOKEN" ]; then
  if [ -f .env ]; then
    set -a; source .env; set +a
  fi
fi

# Verify vars are set
[ -z "$JFROG_URL" ] && echo "FAIL: JFROG_URL is not set" && exit 1
[ -z "$JFROG_ACCESS_TOKEN" ] && echo "FAIL: JFROG_ACCESS_TOKEN is not set" && exit 1
echo "Found credentials for: ${JFROG_URL}"
```

### 1b. Confirm Use of Existing Credentials

If credentials are found, **ask the user to confirm** before using them:

> **Existing JFrog configuration found:**
>
> - **URL**: `{jfrog-url}`
> - **Token**: `****...****` (stored in `.env`)
>
> Would you like to **use** these credentials or **change** them?

**Wait for user response:**
- If **"use"**: Validate existing credentials and proceed
- If **"change"**: Prompt for new credentials (step 2)

### 2. Prompt for Missing Credentials

If `.env` doesn't exist or is missing required fields, **interactively ask the user** through the chat:

> I need to connect to your JFrog Platform. Please provide the following:
>
> 1. **JFrog Platform URL**: The base URL of your JFrog Platform (e.g., `https://mycompany.jfrog.io`)
> 2. **Access Token**: An access token with admin privileges
>
> You can generate an access token from: `https://your-platform.jfrog.io/ui/admin/configuration/security/access_tokens`

**Wait for the user's response** before proceeding.

### 3. Validate the Token

Token validation requires two checks:
1. **Authentication check** - Verify the token is valid
2. **Platform Admin check** - Verify the token has platform admin privileges

#### Step 3a: Validate Authentication

First, verify the token works by calling an authenticated endpoint:

```bash
# Validate token - this endpoint requires authentication
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" \
  -H "Authorization: Bearer ${JFROG_ACCESS_TOKEN}" \
  "${JFROG_URL}/artifactory/api/system/version")

if [ "$HTTP_CODE" = "200" ]; then
  echo "Token authentication successful"
else
  echo "Token authentication failed: HTTP ${HTTP_CODE}"
fi
```

**If authentication fails** (HTTP 401 or 403):
> The provided token is invalid. Please check:
> 1. The token is correctly copied (no extra spaces)
> 2. The JFrog URL is correct
> 3. The token has not expired

#### Step 3b: Validate Platform Admin Privileges

After authentication succeeds, verify the token has **platform admin** privileges:

```bash
# Check platform admin access - this endpoint requires platform admin
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" \
  -H "Authorization: Bearer ${JFROG_ACCESS_TOKEN}" \
  "${JFROG_URL}/access/api/v1/config/security/authentication/basic_authentication_enabled")

if [ "$HTTP_CODE" = "200" ]; then
  echo "Platform admin privileges confirmed"
else
  echo "Platform admin check failed: HTTP ${HTTP_CODE}"
fi
```

**If platform admin check fails** (HTTP 401 or 403):
> The provided token does not have **platform admin** privileges.
>
> This skill requires a platform admin token to:
> - Create JFrog projects
> - Create repositories
> - Configure project settings
>
> Please provide an access token with platform admin privileges.
> You can generate one from: `{jfrog-url}/ui/admin/configuration/security/access_tokens`

**Only proceed if BOTH checks pass.**

#### Step 3c: Check Subscription Type

After admin validation, check the subscription type to determine available features:

```bash
# Get subscription type from license API
SUBSCRIPTION_TYPE=$(curl -s -H "Authorization: Bearer ${JFROG_ACCESS_TOKEN}" \
  "${JFROG_URL}/artifactory/api/system/license" | jq -r '.subscriptionType')

echo "Subscription type: ${SUBSCRIPTION_TYPE}"
```

**Subscription types and OIDC support:**
- `enterprise_xray*` / `enterprise_plus*` - OIDC available
- `enterprise` (base) / `pro` / `pro_x` / `oss` - OIDC NOT available

**Check for OIDC compatibility:**
```bash
if [[ "$SUBSCRIPTION_TYPE" == enterprise_xray* ]] || [[ "$SUBSCRIPTION_TYPE" == enterprise_plus* ]]; then
  OIDC_AVAILABLE=true
else
  OIDC_AVAILABLE=false
fi
```

Store the subscription type for later use when generating GitHub workflows:
- If `enterprise_xray*` or `enterprise_plus*`: Generate workflows with OIDC authentication
- Otherwise: Generate workflows with secret-based authentication

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

Once credentials are loaded from `.env`, use them in API calls:

```bash
# Load credentials
if [ -z "$JFROG_URL" ] || [ -z "$JFROG_ACCESS_TOKEN" ]; then
  if [ -f .env ]; then set -a; source .env; set +a; fi
fi

# Make authenticated API call
curl -X POST "${JFROG_URL}/access/api/v1/projects" \
  -H "Authorization: Bearer ${JFROG_ACCESS_TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{"project_key": "myapp", "display_name": "My App"}'
```

## Security Notes

1. **Never log or display the token** - mask it in any output
2. **Don't commit credentials** - add `.env` to `.gitignore`
3. **Token scope** - must be a platform admin token for onboarding operations

## Troubleshooting

| Issue | Solution |
|-------|----------|
| "Permission denied" reading .env | Check file permissions: `ls -la .env` |
| "No such file" | Run from repo root, or .env not created yet |
| "Connection refused" | Check URL is correct and platform is running |
| "401 Unauthorized" | Token is invalid or expired, regenerate it |
| "403 Forbidden" | Token doesn't have admin privileges |
| "jq: command not found" | Install jq: `brew install jq` (macOS) |
| Credentials committed to git | Add `.env` to `.gitignore` and remove from history |
