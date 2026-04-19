# JFrog Authentication

**Primary:** JFrog CLI **2.100.0+** with **`jf config`** and **`jf api <path>`** (see [../../../platform-features/skills/jfrog-cli/login-flow.md](../../../platform-features/skills/jfrog-cli/login-flow.md) and [../../../platform-features/skills/jfrog-cli/jf-api-patterns.md](../../../platform-features/skills/jfrog-cli/jf-api-patterns.md)). After resolving the server, **show `jf config show` URLs**, ask the user to **confirm** the instance, then run **`jf api /artifactory/api/v1/system/readiness`**.

**Fallback:** `curl` with `Authorization: Bearer $JFROG_ACCESS_TOKEN` when the CLI is missing or below 2.100.0. Do not use Python or other HTTP clients for examples in this repo unless explicitly noted.

## Required tools

```bash
for tool in jf curl jq; do
  command -v $tool >/dev/null 2>&1 && echo "OK: $tool" || echo "MISSING: $tool"
done
```

Install JFrog CLI: [Install JFrog CLI](https://docs.jfrog.com/integrations/docs/download-and-install-the-jfrog-cli).

## Credential storage (primary)

**`jf config`** is the sole credential store for normal operation (encrypted at rest). Use [login-flow.md](../../../platform-features/skills/jfrog-cli/login-flow.md) for web login or `jf config add`.

## Optional `.env` (fallback / manifest parity)

For **`curl`** fallback or comparing `jfrog.url` in manifests, you may keep a `.env` at the **repository root**:

```
JFROG_URL=https://mycompany.jfrog.io
JFROG_ACCESS_TOKEN=eyJ...
```

Add `.env` to `.gitignore`. Only **access tokens** are supported for bearer auth (no username/password for Access API flows in these examples).

## Authentication flow

### 1. Login-flow and platform confirmation

Complete login-flow (install, `jf config`, confirm URL, **`jf api /artifactory/api/v1/system/readiness`**).

### 2. Validate token (prefer `jf api`)

**Authentication check:**

```bash
BODY=/tmp/jf-auth-version.json
CODE=/tmp/jf-auth-version.code
jf api /artifactory/api/system/version >"$BODY" 2>"$CODE"
HTTP_CODE=$(tr -d '\r\n' < "$CODE")
```

**Admin check:**

```bash
BODY=/tmp/jf-auth-admin.json
CODE=/tmp/jf-auth-admin.code
jf api /access/api/v1/config/security/authentication/basic_authentication_enabled >"$BODY" 2>"$CODE"
HTTP_CODE=$(tr -d '\r\n' < "$CODE")
```

**Fallback (`curl`):** same paths under `"${JFROG_URL}/..."` with bearer header.

### 3. Subscription type

```bash
LIC=/tmp/jf-auth-license.json
LICC=/tmp/jf-auth-license.code
jf api /artifactory/api/system/license >"$LIC" 2>"$LICC"
HTTP_CODE=$(tr -d '\r\n' < "$LICC")
SUBSCRIPTION_TYPE=$(jq -r '.subscriptionType' "$LIC")
```

**Fallback:** `curl -s -H "Authorization: Bearer ${JFROG_ACCESS_TOKEN}" "${JFROG_URL}/artifactory/api/system/license" | jq -r '.subscriptionType'`

## Health check

After user confirms the platform, prefer:

```bash
jf api /artifactory/api/v1/system/readiness
```

**Fallback:** `curl -s "${JFROG_URL}/artifactory/api/v1/system/readiness"` (may be unauthenticated depending on instance).

## Example API call (create project)

**Preferred:**

```bash
jf api /access/api/v1/projects -X POST -H "Content-Type: application/json" \
  -d '{"project_key": "myapp", "display_name": "My App"}'
```

**Fallback (`curl`):**

```bash
if [ -z "$JFROG_URL" ] || [ -z "$JFROG_ACCESS_TOKEN" ]; then
  if [ -f .env ]; then set -a; source .env; set +a; fi
fi
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
