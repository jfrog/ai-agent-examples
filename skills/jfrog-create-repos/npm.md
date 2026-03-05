# npm Configuration

This document describes how to set up JFrog repositories for npm packages and configure the local development environment.

## Required Tools

Before proceeding, verify these tools are installed:

```bash
# Check required tools
for tool in curl jq npm node; do
  if ! command -v $tool &> /dev/null; then
    echo "ERROR: $tool is not installed"
  else
    echo "OK: $tool ($(command -v $tool))"
  fi
done
```

**Installation if missing:**

| Tool | macOS | Ubuntu/Debian | Purpose |
|------|-------|---------------|---------|
| curl | `brew install curl` | `sudo apt-get install curl` | API calls |
| jq | `brew install jq` | `sudo apt-get install jq` | JSON parsing |
| node/npm | `brew install node` | `sudo apt-get install nodejs npm` | Package management |

## Repository Structure

For npm, create three repositories:

| Repository | Type | Purpose |
|------------|------|---------|
| `{project}-npm-remote` | Remote | Proxies npmjs.org |
| `{project}-npm-local` | Local | Stores published packages |
| `{project}-npm` | Virtual | User-facing, aggregates both |

## Repository Creation

### 1. Remote Repository (Proxy)

Creates a cache/proxy to npmjs.org:

```bash
curl -X PUT "${JFROG_URL}/artifactory/api/repositories/${PROJECT_KEY}-npm-remote" \
  -H "Authorization: Bearer ${JFROG_ACCESS_TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{
    "key": "'${PROJECT_KEY}'-npm-remote",
    "rclass": "remote",
    "packageType": "npm",
    "url": "https://registry.npmjs.org",
    "projectKey": "'${PROJECT_KEY}'",
    "description": "Proxy cache for npmjs.org"
  }'
```

### 2. Local Repository (Publish Target)

Stores your private/internal packages:

```bash
curl -X PUT "${JFROG_URL}/artifactory/api/repositories/${PROJECT_KEY}-npm-local" \
  -H "Authorization: Bearer ${JFROG_ACCESS_TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{
    "key": "'${PROJECT_KEY}'-npm-local",
    "rclass": "local",
    "packageType": "npm",
    "projectKey": "'${PROJECT_KEY}'",
    "description": "Local repository for published packages"
  }'
```

### 3. Virtual Repository (User-Facing)

Aggregates local and remote -- developers use this URL:

```bash
curl -X PUT "${JFROG_URL}/artifactory/api/repositories/${PROJECT_KEY}-npm" \
  -H "Authorization: Bearer ${JFROG_ACCESS_TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{
    "key": "'${PROJECT_KEY}'-npm",
    "rclass": "virtual",
    "packageType": "npm",
    "repositories": ["'${PROJECT_KEY}'-npm-local", "'${PROJECT_KEY}'-npm-remote"],
    "defaultDeploymentRepo": "'${PROJECT_KEY}'-npm-local",
    "projectKey": "'${PROJECT_KEY}'",
    "description": "Virtual npm repository - use this for install and publish"
  }'
```

## Local Development Configuration

### .npmrc File

Create or update `.npmrc` in the project root to point to JFrog:

```bash
# Load credentials from .env
if [ -z "$JFROG_URL" ] || [ -z "$JFROG_ACCESS_TOKEN" ]; then
  if [ -f .env ]; then set -a; source .env; set +a; fi
fi

PROJECT_KEY=your-project-key
JFROG_HOSTNAME="${JFROG_URL#https://}"

cat > .npmrc << EOF
registry=${JFROG_URL}/artifactory/api/npm/${PROJECT_KEY}-npm/
//${JFROG_HOSTNAME}/artifactory/api/npm/${PROJECT_KEY}-npm/:_authToken=${JFROG_ACCESS_TOKEN}
always-auth=true
EOF
```

```ini
# Registry configuration - all packages resolve through JFrog
registry=https://{jfrog-url}/artifactory/api/npm/{project}-npm/

# Authentication for publishing
//{jfrog-url}/artifactory/api/npm/{project}-npm/:_authToken=eyJ...

# Always authenticate (required for private packages)
always-auth=true
```

**Example** for project `myapp` on `mycompany.jfrog.io`:

```ini
registry=https://mycompany.jfrog.io/artifactory/api/npm/myapp-npm/
//mycompany.jfrog.io/artifactory/api/npm/myapp-npm/:_authToken=eyJ...
always-auth=true
```
**Important**: Add `.npmrc` to `.gitignore` if it contains a token.

## Usage

### Installing Dependencies

With `.npmrc` configured, npm commands work normally:

```bash
# Dependencies resolve through JFrog (cached from npmjs.org)
npm install

# Install specific package
npm install lodash
```

### Publishing Packages

Publishing goes to the local repository through the virtual:

```bash
# Ensure package.json has correct name and version
npm publish
```

The virtual repository's `defaultDeploymentRepo` routes publishes to `{project}-npm-local`.

## Verification

### Test Dependency Resolution

```bash
# Clear npm cache and reinstall
rm -rf node_modules package-lock.json
npm cache clean --force
npm install

# Check that packages came from JFrog
npm config get registry
# Should show: https://mycompany.jfrog.io/artifactory/api/npm/myapp-npm/
```

### Test Publishing

```bash
# Create a test package
mkdir test-pkg && cd test-pkg
npm init -y
echo "module.exports = 'test';" > index.js

# Publish (use --dry-run first)
npm publish --dry-run

# If dry run succeeds, publish for real
npm publish
```

### Verify Package in JFrog

After publishing, the package should appear in JFrog:

```bash
curl -s -H "Authorization: Bearer ${JFROG_ACCESS_TOKEN}" \
  "${JFROG_URL}/artifactory/api/npm/${PROJECT_KEY}-npm-local/-/all"
```

## Scoped Packages

For scoped packages (`@myorg/package`), add scope configuration:

```ini
# .npmrc
registry=https://mycompany.jfrog.io/artifactory/api/npm/myapp-npm/
@myorg:registry=https://mycompany.jfrog.io/artifactory/api/npm/myapp-npm/
//mycompany.jfrog.io/artifactory/api/npm/myapp-npm/:_authToken=eyJ...
always-auth=true
```

## Troubleshooting

| Issue | Solution |
|-------|----------|
| `401 Unauthorized` during install | Check the token in `.npmrc` is correct |
| `403 Forbidden` during publish | Token may lack publish permissions |
| `ENOTFOUND` | Check registry URL is correct |
| Packages not caching | Verify remote repository URL is correct |
| Old package versions | Clear npm cache: `npm cache clean --force` |
