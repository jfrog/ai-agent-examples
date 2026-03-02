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

## Config File Location

Credentials are stored at the **repository level** in `.jfrog/config`:

```
{repo-root}/.jfrog/config
```

This ensures project isolation - each repository can have its own JFrog configuration without clashing with other projects.

**Important**: Add `.jfrog/` to your `.gitignore` to avoid committing credentials.

## Config File Format

The config file is JSON format:

```json
{
  "url": "https://mycompany.jfrog.io",
  "token": "eyJ..."
}
```

**Important**: Only access tokens are supported. Username/password authentication is NOT supported because the JFrog Access API (used for project creation) requires bearer token authentication.

## Authentication Flow

### 1. Check for Existing Credentials

```bash
# Check if config file exists and read it
if [ -f .jfrog/config ]; then
  JFROG_URL=$(cat .jfrog/config | jq -r '.url')
  JFROG_TOKEN=$(cat .jfrog/config | jq -r '.token')
  echo "Found existing credentials for: ${JFROG_URL}"
fi
```

### 1b. Confirm Use of Existing Credentials

If credentials are found, **ask the user to confirm** before using them:

> **Existing JFrog configuration found:**
> 
> - **URL**: `{jfrog-url}`
> - **Token**: `****...****` (stored in `.jfrog/config`)
> 
> Would you like to **use** these credentials or **change** them?

**Wait for user response:**
- If **"use"**: Validate existing credentials and proceed
- If **"change"**: Prompt for new credentials (step 2)

### 2. Prompt for Missing Credentials

If `.jfrog/config` doesn't exist or is missing required fields, **interactively ask the user** through the chat:

> I need to connect to your JFrog Platform. Please provide the following:
>
> 1. **JFrog Platform URL**: The base URL of your JFrog Platform (e.g., `https://mycompany.jfrog.io`)
> 2. **Access Token**: An access token with admin privileges
>
> You can generate an access token from: `https://your-platform.jfrog.io/ui/admin/configuration/security/access_tokens`

**Wait for the user's response** before proceeding. The user will typically provide:
- URL and token in the same message, or
- One value at a time

Example user responses:
```
"URL is https://acme.jfrog.io and my token is eyJ..."
```
or
```
"https://acme.jfrog.io"
"eyJhbGciOiJSUzI1NiIs..."
```

Parse the user's response to extract the URL and token values.

### 3. Validate the Token

Token validation requires two checks:
1. **Authentication check** - Verify the token is valid
2. **Platform Admin check** - Verify the token has platform admin privileges

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
  echo "✓ Platform admin privileges confirmed"
else
  echo "✗ Platform admin check failed: HTTP ${HTTP_CODE}"
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
> Please provide an access token with platform admin privileges.
> You can generate one from: `{jfrog-url}/ui/admin/configuration/security/access_tokens`

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

### 4. Save Credentials Securely

After validation succeeds, save the credentials with restricted permissions:

```bash
# Create directory if it doesn't exist
mkdir -p .jfrog

# Write config file
cat > .jfrog/config << EOF
{
  "url": "${JFROG_URL}",
  "token": "${JFROG_TOKEN}"
}
EOF

# Restrict permissions (owner read/write only)
chmod 600 .jfrog/config

# Add to .gitignore if not already present
if ! grep -q "^\.jfrog/$" .gitignore 2>/dev/null; then
  echo ".jfrog/" >> .gitignore
fi
```

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
# Load credentials from repo-level config
JFROG_URL=$(cat .jfrog/config | jq -r '.url')
JFROG_TOKEN=$(cat .jfrog/config | jq -r '.token')

# Make authenticated API call
curl -X POST "${JFROG_URL}/unifiedpolicy/api/v1/templates" \
  -H "Authorization: Bearer ${JFROG_TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{"description": "test template", "name": "test Template", "category": "workflow", "parameters": [],"rego": "package curation.policies\n\nimport rego.v1\n\nallow := {\n    \"should_allow\": true,\n}", "scanners": "noop"],"version": "1.0.0","data_source_type": "noop","is_custom": true}'
```

## Security Notes

1. **Never log or display the token** - mask it in any output
2. **Config file permissions** - must be `600` (owner read/write only)
3. **Don't commit credentials** - add `.jfrog/` to `.gitignore`
4. **Token scope** - assume admin privileges but don't verify explicitly

## Future: User-Level Configuration

Currently, all configuration is at the project level (`.jfrog/config`). In a future update, we will add support for user-level configuration at `~/.jfrog/config` with the following precedence:

1. Project-level `.jfrog/config` (highest priority)
2. User-level `~/.jfrog/config` (fallback)

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