---
name: jfrog-oidc-setup
description: Configure OpenID Connect (OIDC) integration between GitHub Actions and JFrog Platform for secretless CI authentication. Checks subscription compatibility, creates OIDC providers, and sets up identity mappings per repository. Use when setting up OIDC for GitHub Actions workflows.
---

# JFrog OIDC Setup

Prefer **`jf api`** per [../../../platform-features/skills/jfrog-cli/jf-api-patterns.md](../../../platform-features/skills/jfrog-cli/jf-api-patterns.md) for JFrog REST calls; **`curl`** in examples is **fallback** when the CLI is unavailable.

Configures OpenID Connect (OIDC) integration between GitHub Actions and JFrog Platform, enabling secretless authentication for CI workflows.

## Overview

OIDC allows GitHub Actions workflows to authenticate with JFrog without storing long-lived secrets. GitHub issues short-lived tokens that JFrog validates and exchanges for access.

```
GitHub Actions  -->  GitHub OIDC Provider  -->  JFrog Platform
     |                      |                        |
     | 1. Request token     |                        |
     |--------------------->|                        |
     |                      |                        |
     | 2. JWT token         |                        |
     |<---------------------|                        |
     |                      |                        |
     | 3. Present JWT       |                        |
     |---------------------------------------------->|
     |                      |                        |
     |                      |    4. Validate & grant |
     |<----------------------------------------------|
```

## Inputs

- `project_key` -- JFrog project key
- `github_repos` -- list of owner/repo (e.g., `["myorg/my-app", "myorg/my-lib"]`)
- `github_host` -- GitHub host (e.g., `github.com` or `github.mycompany.com`)
- `OIDC_SETUP` -- boolean from manifest `github.oidc_setup` key (user's preference)
- `OIDC_AVAILABLE` -- boolean from prerequisite subscription check

## Step 0: Check OIDC Setup Preference and Availability

First, check the user's preference from the manifest (`OIDC_SETUP`). Then verify platform support (`OIDC_AVAILABLE`).

**If `OIDC_SETUP` is `false`**: skip the entire skill regardless of subscription and return:
- `oidc_provider_name` = empty string
- Log: `INFO: OIDC setup is disabled in manifest (github.oidc_setup: false). CI workflows will use secrets-based authentication.`

**If `OIDC_SETUP` is `true` AND `OIDC_AVAILABLE` is `false`**: **ABORT immediately** and return an error:
- Log: `ABORT: OIDC was requested (github.oidc_setup: true) but the JFrog subscription does not support it. Upgrade to Enterprise X or Enterprise+, or set github.oidc_setup: false.`
- Do **not** proceed with any OIDC configuration. This is a hard stop.

**If `OIDC_SETUP` is `true` AND `OIDC_AVAILABLE` is `true`**: proceed with the steps below.

### Decision Matrix

| `github.oidc_setup` | Subscription supports OIDC | Result |
|----------------------|---------------------------|--------|
| `true` | Yes | Proceed with OIDC setup |
| `true` | No | **ABORT** -- platform cannot provide requested OIDC |
| `false` | Yes or No | Skip OIDC, use secrets-based auth |

### Subscription Check (if not already done)

```bash
jf api /artifactory/api/system/license >/tmp/oidc-license.json 2>/tmp/oidc-license.code
SUBSCRIPTION_TYPE=$(jq -r '.subscriptionType' /tmp/oidc-license.json)

if [[ "$SUBSCRIPTION_TYPE" == enterprise_xray* ]] || [[ "$SUBSCRIPTION_TYPE" == enterprise_plus* ]]; then
  OIDC_AVAILABLE=true
  echo "OK: OIDC is available (subscription: $SUBSCRIPTION_TYPE)"
else
  OIDC_AVAILABLE=false
fi

# Enforce manifest preference
if [ "$OIDC_SETUP" = "false" ]; then
  echo "INFO: OIDC setup is disabled in manifest (github.oidc_setup: false). Skipping."
  exit 0
fi

if [ "$OIDC_AVAILABLE" = "false" ]; then
  echo "ABORT: OIDC was requested (github.oidc_setup: true) but the JFrog subscription"
  echo "       ($SUBSCRIPTION_TYPE) does not support OIDC."
  echo ""
  echo "To fix this, either:"
  echo "  1. Upgrade to an Enterprise X or Enterprise+ subscription, OR"
  echo "  2. Set 'github.oidc_setup: false' in the manifest to use secrets-based auth."
  exit 1
fi
```

## Step 1: Determine GitHub Type

Based on `github_host` from the manifest:

| GitHub Type | Host Pattern | OIDC Issuer URL |
|-------------|-------------|-----------------|
| **Public GitHub** | `github.com` | `https://token.actions.githubusercontent.com` |
| **GitHub Enterprise** | any other host | `https://{github_host}/_services/token` |

```bash
if [ "$GITHUB_HOST" = "github.com" ]; then
  ISSUER_URL="https://token.actions.githubusercontent.com"
  PROVIDER_TYPE="GitHub"
else
  ISSUER_URL="https://${GITHUB_HOST}/_services/token"
  PROVIDER_TYPE="Generic"  # Use Generic for GHE to avoid org validation errors
fi
```

**Important**: Use `provider_type: "GitHub"` only for public GitHub (github.com). For GitHub Enterprise, use `"Generic"` to avoid organization validation errors where the JFrog platform cannot reach the GHE host.

## Step 2: Check for Existing OIDC Provider or Create One

### Check existing providers (run with `required_permissions: ["full_network"]`)

```bash
jf api /access/api/v1/oidc >/tmp/oidc-providers.json 2>/tmp/oidc-providers.code
PROVIDERS=$(cat /tmp/oidc-providers.json)

# Check if a provider with the correct issuer_url already exists
EXISTING_PROVIDER=$(echo "$PROVIDERS" | jq -r --arg url "$ISSUER_URL" \
  '.[] | select(.issuer_url == $url) | .name')

if [ -n "$EXISTING_PROVIDER" ]; then
  echo "Reusing existing OIDC provider: ${EXISTING_PROVIDER}"
  PROVIDER_NAME="$EXISTING_PROVIDER"
else
  echo "No matching provider found. Creating one..."
fi
```

### Create provider if needed (run with `required_permissions: ["full_network"]`)

```bash
# Choose a provider name
if [ "$PROVIDER_TYPE" = "GitHub" ]; then
  PROVIDER_NAME="github-oidc"
else
  PROVIDER_NAME="github-enterprise-oidc"
fi

jf api /access/api/v1/oidc -X POST \
  -H "Content-Type: application/json" \
  -d '{
    "name": "'"$PROVIDER_NAME"'",
    "issuer_url": "'"$ISSUER_URL"'",
    "provider_type": "'"$PROVIDER_TYPE"'"
  }'
```

**API notes:**
- `issuer_url` must be a **top-level field** (not nested inside a `configuration` object)
- 409 = provider already exists -- treat as success

## Step 3: Create Identity Mappings for Each Repository

For **each repo** in `github_repos`, check if an identity mapping already exists and create one if needed.

### Check existing mappings (run with `required_permissions: ["full_network"]`)

```bash
jf api "/access/api/v1/oidc/${PROVIDER_NAME}/identity_mappings" >/tmp/oidc-mappings.json 2>/dev/null
MAPPINGS=$(cat /tmp/oidc-mappings.json)

REPO="owner/repo"  # from github_repos[]

# Check if an existing mapping already covers the repo
EXISTING_MAPPING=$(echo "$MAPPINGS" | jq -r --arg repo "$REPO" \
  '.[] | select(.claims.repository == $repo) | .name')
```

### Create mapping for main branch (deploy access)

If no existing mapping covers the repo:

```bash
# Sanitize repo name for mapping name (replace / with -)
MAPPING_NAME=$(echo "$REPO" | tr '/' '-')

jf api /access/api/v1/oidc/${PROVIDER_NAME}/identity_mappings -X POST \
  -H "Content-Type: application/json" \
  -d '{
    "name": "'"${MAPPING_NAME}-main"'",
    "project": "'"${PROJECT_KEY}"'",
    "priority": 100,
    "claims": {
      "repository": "'"$REPO"'",
      "ref": "refs/heads/main"
    },
    "token_spec": {
      "scope": "applied-permissions/roles:'"${PROJECT_KEY}"':Developer",
      "expires_in": 300
    }
  }'
```

### Create mapping for PRs (read-only access)

```bash
jf api /access/api/v1/oidc/${PROVIDER_NAME}/identity_mappings -X POST \
  -H "Content-Type: application/json" \
  -d '{
    "name": "'"${MAPPING_NAME}-pr"'",
    "project": "'"${PROJECT_KEY}"'",
    "priority": 90,
    "claims": {
      "repository": "'"$REPO"'"
    },
    "token_spec": {
      "scope": "applied-permissions/roles:'"${PROJECT_KEY}"':Developer",
      "expires_in": 300
    }
  }'
```

**Important notes:**
- The `scope` must include the project key: `applied-permissions/roles:{PROJECT_KEY}:Developer` (not just `applied-permissions/roles:Developer`, which returns `"token_spec Invalid scope"`)
- Higher priority mappings are evaluated first -- main branch (100) matches before general repo (90)
- 409 = mapping already exists -- treat as success

## Step 4: Report Results

After processing all repos, return:
- `oidc_provider_name` -- the provider name (e.g., `github-oidc`) for use in CI workflows
- Summary of identity mappings created or reused

Inform the user:
> OIDC has been configured. The CI workflow skill will use `oidc-provider-name: {provider_name}` in the `setup-jfrog-cli` action.

## Error Handling

- **409 Conflict**: Provider or mapping already exists -- treat as success
- **400 Bad Request**: Check the request body format, especially `issuer_url` placement
- **"oidc_setting Organization is not valid"**: Use `provider_type: "Generic"` for GitHub Enterprise
- **"token_spec Invalid scope"**: Ensure scope includes the project key in the role path

## GitHub Token Claims Reference

GitHub OIDC tokens include claims that identify the source:

| Claim | Example | Description |
|-------|---------|-------------|
| `sub` | `repo:owner/repo:ref:refs/heads/main` | Subject claim |
| `repository` | `owner/repo` | Repository full name |
| `repository_owner` | `owner` | Organization or user |
| `ref` | `refs/heads/main` | Git ref |
| `job_workflow_ref` | `owner/repo/.github/workflows/ci.yml@refs/heads/main` | Workflow reference |

## Permission Scopes

| Scope | Description |
|-------|-------------|
| `applied-permissions/roles:{PROJECT_KEY}:Developer` | Read and deploy access to project repositories (use for CI) |
| `applied-permissions/roles:{PROJECT_KEY}:Contributor` | Read, deploy, and manage access |
| `applied-permissions/roles:{PROJECT_KEY}:Release Manager` | Full control over project artifacts |

## Troubleshooting

| Issue | Solution |
|-------|----------|
| "oidc_setting Organization is not valid" | Use `provider_type: "Generic"` for GitHub Enterprise |
| "issuer_url must not be blank" | `issuer_url` must be a top-level field, not nested |
| "token_spec Invalid scope" | Include project key in scope: `roles:{PROJECT_KEY}:Developer` |
| "OIDC provider not found" | Verify provider name matches in JFrog and workflow |
| "No identity mapping matched" | Check claims JSON matches GitHub token claims (case-sensitive) |
| "Permission denied" | Verify token scope and that JFrog groups have repo access |

## Debug: View GitHub Token Claims

Add this step to a workflow to inspect the claims:

```yaml
- name: Debug OIDC token
  run: |
    TOKEN=$(curl -s -H "Authorization: bearer $ACTIONS_ID_TOKEN_REQUEST_TOKEN" \
      "$ACTIONS_ID_TOKEN_REQUEST_URL&audience=jfrog" | jq -r '.value')
    echo "Token claims:"
    echo $TOKEN | cut -d'.' -f2 | base64 -d 2>/dev/null | jq .
```
