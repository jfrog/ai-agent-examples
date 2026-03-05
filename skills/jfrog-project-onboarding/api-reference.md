# JFrog REST API Reference

This document provides curl examples for all JFrog REST API calls used in the onboarding workflow.
Always use `curl` for REST API calls; do not use Python or other HTTP clients.

## Required Tools

Before running API calls, verify these tools are installed:

```bash
# Check required tools
for tool in curl jq; do
  if ! command -v $tool &> /dev/null; then
    echo "ERROR: $tool is not installed"
    case $tool in
      curl) echo "  Install: brew install curl (macOS) or apt-get install curl (Linux)" ;;
      jq)   echo "  Install: brew install jq (macOS) or apt-get install jq (Linux)" ;;
    esac
  fi
done
```

## Prerequisites

Load credentials from `.env` before making API calls:

```bash
# Load .env if vars are not already set
if [ -z "$JFROG_URL" ] || [ -z "$JFROG_ACCESS_TOKEN" ]; then
  if [ -f .env ]; then set -a; source .env; set +a; fi
fi
```

## Health & Validation

### System Readiness (Unauthenticated)

Check if the JFrog Platform is accessible:

```bash
curl -s "${JFROG_URL}/artifactory/api/v1/system/readiness"
```

**Response** (HTTP 200):
```json
{"status": "OK"}
```

### Validate Token (Authenticated)

Verify the token is valid:

```bash
curl -s -f -H "Authorization: Bearer ${JFROG_ACCESS_TOKEN}" \
  "${JFROG_URL}/artifactory/api/system/version"
```

**Response** (HTTP 200):
```json
{
  "version": "7.77.3",
  "revision": "77300900",
  "addons": []
}
```

### Validate Platform Admin Privileges

After verifying the token is valid, check if it has **platform admin** privileges:

```bash
curl -s -o /dev/null -w "%{http_code}" \
  -H "Authorization: Bearer ${JFROG_ACCESS_TOKEN}" \
  "${JFROG_URL}/access/api/v1/config/security/authentication/basic_authentication_enabled"
```

**Response codes:**
- `200` = Token has platform admin privileges
- `401` = Token is invalid
- `403` = Token is valid but NOT a platform admin

**Note:** This endpoint requires platform admin access. If the token returns 401 or 403, it cannot be used for creating projects and repositories.

### Check Subscription/License Type

Check the JFrog subscription type to determine available features:

```bash
curl -s -H "Authorization: Bearer ${JFROG_ACCESS_TOKEN}" \
  "${JFROG_URL}/artifactory/api/system/license"
```

**Response** (HTTP 200):
```json
{
  "type": "Enterprise",
  "validThrough": "Dec 31, 2026",
  "licensedTo": "Company Name",
  "subscriptionType": "enterprise_plus"
}
```

**Subscription types (`subscriptionType` field):**
- `enterprise_xray*` / `enterprise_plus*` - OIDC available
- `enterprise` (without xray/plus suffix) - NO OIDC support
- `pro` / `pro_x` - NO OIDC support
- `oss` / `community` - NO OIDC support

**Check for OIDC-compatible subscription:**
```bash
SUBSCRIPTION_TYPE=$(curl -s -H "Authorization: Bearer ${JFROG_ACCESS_TOKEN}" \
  "${JFROG_URL}/artifactory/api/system/license" | jq -r '.subscriptionType')

if [[ "$SUBSCRIPTION_TYPE" == enterprise_xray* ]] || [[ "$SUBSCRIPTION_TYPE" == enterprise_plus* ]]; then
  echo "${SUBSCRIPTION_TYPE} subscription - OIDC available"
else
  echo "${SUBSCRIPTION_TYPE} subscription - OIDC not available"
fi
```

## Projects

### Create Project

```bash
curl -X POST "${JFROG_URL}/access/api/v1/projects" \
  -H "Authorization: Bearer ${JFROG_ACCESS_TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{
    "project_key": "myapp",
    "display_name": "My Application",
    "description": "Project for myapp artifacts"
  }'
```

**Response** (HTTP 201):
```json
{
  "project_key": "myapp",
  "display_name": "My Application",
  "description": "Project for myapp artifacts"
}
```

### Check if Project Exists

```bash
curl -s -o /dev/null -w "%{http_code}" \
  -H "Authorization: Bearer ${JFROG_ACCESS_TOKEN}" \
  "${JFROG_URL}/access/api/v1/projects/myapp"
```

- `200` = project exists
- `404` = project doesn't exist

### Get Project Details

```bash
curl -s -H "Authorization: Bearer ${JFROG_ACCESS_TOKEN}" \
  "${JFROG_URL}/access/api/v1/projects/myapp"
```

## Repositories

### Create Local Repository

Local repositories store your published artifacts.

**npm**:
```bash
curl -X PUT "${JFROG_URL}/artifactory/api/repositories/myapp-npm-local" \
  -H "Authorization: Bearer ${JFROG_ACCESS_TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{
    "key": "myapp-npm-local",
    "rclass": "local",
    "packageType": "npm",
    "projectKey": "myapp",
    "description": "Local npm repository for myapp"
  }'
```

**Docker**:
```bash
curl -X PUT "${JFROG_URL}/artifactory/api/repositories/myapp-docker-local" \
  -H "Authorization: Bearer ${JFROG_ACCESS_TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{
    "key": "myapp-docker-local",
    "rclass": "local",
    "packageType": "docker",
    "projectKey": "myapp",
    "description": "Local Docker repository for myapp"
  }'
```

### Create Remote Repository

Remote repositories proxy external registries.

**npm** (proxies npmjs.org):
```bash
curl -X PUT "${JFROG_URL}/artifactory/api/repositories/myapp-npm-remote" \
  -H "Authorization: Bearer ${JFROG_ACCESS_TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{
    "key": "myapp-npm-remote",
    "rclass": "remote",
    "packageType": "npm",
    "url": "https://registry.npmjs.org",
    "projectKey": "myapp",
    "description": "Remote proxy for npmjs.org"
  }'
```

**Docker** (proxies Docker Hub):
```bash
curl -X PUT "${JFROG_URL}/artifactory/api/repositories/myapp-docker-remote" \
  -H "Authorization: Bearer ${JFROG_ACCESS_TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{
    "key": "myapp-docker-remote",
    "rclass": "remote",
    "packageType": "docker",
    "url": "https://registry-1.docker.io",
    "projectKey": "myapp",
    "description": "Remote proxy for Docker Hub"
  }'
```

### Create Virtual Repository

Virtual repositories aggregate local and remote repositories. Developers use these.

**npm**:
```bash
curl -X PUT "${JFROG_URL}/artifactory/api/repositories/myapp-npm" \
  -H "Authorization: Bearer ${JFROG_ACCESS_TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{
    "key": "myapp-npm",
    "rclass": "virtual",
    "packageType": "npm",
    "repositories": ["myapp-npm-local", "myapp-npm-remote"],
    "defaultDeploymentRepo": "myapp-npm-local",
    "projectKey": "myapp",
    "description": "Virtual npm repository for myapp (use this for npm install/publish)"
  }'
```

**Docker**:
```bash
curl -X PUT "${JFROG_URL}/artifactory/api/repositories/myapp-docker" \
  -H "Authorization: Bearer ${JFROG_ACCESS_TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{
    "key": "myapp-docker",
    "rclass": "virtual",
    "packageType": "docker",
    "repositories": ["myapp-docker-local", "myapp-docker-remote"],
    "defaultDeploymentRepo": "myapp-docker-local",
    "projectKey": "myapp",
    "description": "Virtual Docker registry for myapp (use this for docker pull/push)"
  }'
```

### Check if Repository Exists

```bash
curl -s -o /dev/null -w "%{http_code}" \
  -H "Authorization: Bearer ${JFROG_ACCESS_TOKEN}" \
  "${JFROG_URL}/artifactory/api/repositories/myapp-npm"
```

- `200` = repository exists
- `400` = repository doesn't exist

### List Repositories

List all repositories:
```bash
curl -s -H "Authorization: Bearer ${JFROG_ACCESS_TOKEN}" \
  "${JFROG_URL}/artifactory/api/repositories"
```

Filter by type:
```bash
curl -s -H "Authorization: Bearer ${JFROG_ACCESS_TOKEN}" \
  "${JFROG_URL}/artifactory/api/repositories?type=virtual"
```

Filter by package type:
```bash
curl -s -H "Authorization: Bearer ${JFROG_ACCESS_TOKEN}" \
  "${JFROG_URL}/artifactory/api/repositories?packageType=npm"
```

## Xray

### Check Xray Availability

Check if JFrog Xray is available and enabled on the platform:

```bash
XRAY_RESPONSE=$(curl -s -H "Authorization: Bearer ${JFROG_ACCESS_TOKEN}" \
  -H "Content-Type: application/json" \
  "${JFROG_URL}/artifactory/api/xrayRepo/getIntegrationConfig")

XRAY_ENABLED=$(echo "$XRAY_RESPONSE" | jq -r '.xrayEnabled')
```

**Interpretation:**
- `XRAY_ENABLED="true"` = Xray is available and enabled
- `XRAY_ENABLED="false"` or null/empty = Xray is not available

### Get Binary Manager ID

Discover the binary manager ID (required for the indexing API):

```bash
BIN_MGR_ID=$(curl -s -H "Authorization: Bearer ${JFROG_ACCESS_TOKEN}" \
  "${JFROG_URL}/xray/api/v1/binMgr" \
  | jq -r '.[0].bin_mgr_id // "default"')
```

### Enable Xray Indexing on Repositories

Configure Xray to index (scan) specific repositories using `PUT /xray/api/v1/binMgr/{id}/repos` ([docs](https://jfrog.com/help/r/xray-rest-apis/update-repos-indexing-configuration)). Only **local** and **remote** repositories should be indexed (not virtual).

```bash
curl -X PUT "${JFROG_URL}/xray/api/v1/binMgr/${BIN_MGR_ID}/repos" \
  -H "Authorization: Bearer ${JFROG_ACCESS_TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{
    "indexed_repos": [
      {"name": "myapp-npm-local", "type": "local", "pkg_type": "npm"},
      {"name": "myapp-npm-remote", "type": "remote", "pkg_type": "npm"},
      {"name": "myapp-docker-local", "type": "local", "pkg_type": "docker"},
      {"name": "myapp-docker-remote", "type": "remote", "pkg_type": "docker"}
    ]
  }'
```

**Notes:**
- Only include repositories that were actually created during onboarding.
- Virtual repositories do not need to be indexed -- Xray scans artifacts in local and remote repos.

## Error Handling

### Common HTTP Status Codes

| Code | Meaning | Action |
|------|---------|--------|
| 200 | Success | Continue |
| 201 | Created | Resource created successfully |
| 400 | Bad Request | Check request body/parameters |
| 401 | Unauthorized | Token invalid or expired |
| 403 | Forbidden | Token lacks required permissions |
| 404 | Not Found | Resource doesn't exist |
| 409 | Conflict | Resource already exists |

### Error Response Format

```json
{
  "errors": [
    {
      "status": 400,
      "message": "Repository key already exists"
    }
  ]
}
```

### Handling "Already Exists" Errors

When creating resources, check if they exist first or handle 409 errors gracefully:

```bash
# Check if repository exists before creating
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" \
  -H "Authorization: Bearer ${JFROG_ACCESS_TOKEN}" \
  "${JFROG_URL}/artifactory/api/repositories/myapp-npm")

if [ "$HTTP_CODE" = "200" ]; then
  echo "Repository already exists, skipping creation"
else
  # Create repository
  curl -X PUT "${JFROG_URL}/artifactory/api/repositories/myapp-npm" ...
fi
```

## Complete Onboarding Script Example

Here's a complete example creating all resources for an npm project:

```bash
#!/bin/bash
set -e

# Load credentials from .env
if [ -z "$JFROG_URL" ] || [ -z "$JFROG_ACCESS_TOKEN" ]; then
  if [ -f .env ]; then set -a; source .env; set +a; fi
fi

PROJECT_KEY="myapp"

# 1. Create project
echo "Creating project..."
curl -X POST "${JFROG_URL}/access/api/v1/projects" \
  -H "Authorization: Bearer ${JFROG_ACCESS_TOKEN}" \
  -H "Content-Type: application/json" \
  -d "{\"project_key\": \"${PROJECT_KEY}\", \"display_name\": \"My App\"}"

# 2. Create remote repository
echo "Creating remote repository..."
curl -X PUT "${JFROG_URL}/artifactory/api/repositories/${PROJECT_KEY}-npm-remote" \
  -H "Authorization: Bearer ${JFROG_ACCESS_TOKEN}" \
  -H "Content-Type: application/json" \
  -d "{\"key\": \"${PROJECT_KEY}-npm-remote\", \"rclass\": \"remote\", \"packageType\": \"npm\", \"url\": \"https://registry.npmjs.org\", \"projectKey\": \"${PROJECT_KEY}\"}"

# 3. Create local repository
echo "Creating local repository..."
curl -X PUT "${JFROG_URL}/artifactory/api/repositories/${PROJECT_KEY}-npm-local" \
  -H "Authorization: Bearer ${JFROG_ACCESS_TOKEN}" \
  -H "Content-Type: application/json" \
  -d "{\"key\": \"${PROJECT_KEY}-npm-local\", \"rclass\": \"local\", \"packageType\": \"npm\", \"projectKey\": \"${PROJECT_KEY}\"}"

# 4. Create virtual repository
echo "Creating virtual repository..."
curl -X PUT "${JFROG_URL}/artifactory/api/repositories/${PROJECT_KEY}-npm" \
  -H "Authorization: Bearer ${JFROG_ACCESS_TOKEN}" \
  -H "Content-Type: application/json" \
  -d "{\"key\": \"${PROJECT_KEY}-npm\", \"rclass\": \"virtual\", \"packageType\": \"npm\", \"repositories\": [\"${PROJECT_KEY}-npm-local\", \"${PROJECT_KEY}-npm-remote\"], \"defaultDeploymentRepo\": \"${PROJECT_KEY}-npm-local\", \"projectKey\": \"${PROJECT_KEY}\"}"

echo "Done!"
```
