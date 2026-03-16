---
name: jfrog-system-config-repo
description: Persist and retrieve onboarding manifests via Artifactory or Git. Supports configurable project/repo for Artifactory and clone/commit/push for Git. Routes by state.destination in the manifest. Use when persisting or retrieving onboarding manifests.
---

# JFrog State Persistence

Manages manifest persistence for onboarding audit trails. Supports two backends:

- **Artifactory** (default) -- stores manifests in a dedicated JFrog generic repository
- **Git** -- commits and pushes manifests to a git repository

The backend is determined by `state.destination` in the manifest (defaults to `artifactory`).

## Inputs (from manifest `state` section)

| Field | Default | Description |
|-------|---------|-------------|
| `state.destination` | `artifactory` | `artifactory` or `git` |
| `state.artifactory.project` | `system` | JFrog project key for manifest storage |
| `state.artifactory.repository` | `system-configuration` | Generic repo key within the project |
| `state.git.repo` | (required if git) | Git repo in `owner/repo` format |
| `state.git.path` | `/` | Directory path in the git repo |
| `state.git.branch` | `main` | Branch to commit to |

If the `state` section is missing from the manifest, default to Artifactory with `system` / `system-configuration`.

## Constants

- **Upload path pattern**: `<ISO-8601-timestamp>/jfrog-configuration-manifest.yaml`
  - Timestamp format: `YYYY-MM-DDTHH-MM-SSZ` (e.g., `2026-02-17T15-30-00Z`)
  - Same pattern for both Artifactory and git backends

## Security (Artifactory backend)

The Artifactory state project is restricted to **platform admins only**:

- All `admin_privileges` are set to `false` (no project-level admin can manage members or resources)
- **No users or groups are ever added** to this project
- Only the platform admin token (used for onboarding operations) has read/write access
- Do **not** include the state project in the manifest's `jfrog_projects` list -- it is internal infrastructure managed by the onboarding agent

This applies to both the default `system` project and any custom project configured via `state.artifactory.project`.

## Routing

Before any operation, read `state.destination` from the manifest (default: `artifactory`):

```bash
DESTINATION=$(yq -r '.state.destination // "artifactory"' "$MANIFEST_FILE")
```

Then branch to the appropriate backend operations below.

## Operations

### 0. Load credentials

```bash
if [ -z "$JFROG_URL" ] || [ -z "$JFROG_ACCESS_TOKEN" ]; then
  if [ -f .env ]; then
    set -a; source .env; set +a
  fi
fi
```

### Read configurable parameters

```bash
# Artifactory backend params (used when destination = artifactory)
STATE_PROJECT=$(yq -r '.state.artifactory.project // "system"' "$MANIFEST_FILE")
STATE_REPO=$(yq -r '.state.artifactory.repository // "system-configuration"' "$MANIFEST_FILE")

# Git backend params (used when destination = git)
STATE_GIT_REPO=$(yq -r '.state.git.repo // ""' "$MANIFEST_FILE")
STATE_GIT_PATH=$(yq -r '.state.git.path // ""' "$MANIFEST_FILE")
STATE_GIT_BRANCH=$(yq -r '.state.git.branch // "main"' "$MANIFEST_FILE")
GITHUB_HOST=$(yq -r '.github.host // "github.com"' "$MANIFEST_FILE")
```

---

## Artifactory Backend Operations

Use these when `state.destination` = `artifactory`.

### Operation A: Ensure Project and Repo Exist (Idempotent)

Run with `required_permissions: ["full_network"]`.

#### A1. Check/create the project

```bash
STATUS=$(curl -s -o /dev/null -w '%{http_code}' \
  -H "Authorization: Bearer $JFROG_ACCESS_TOKEN" \
  "$JFROG_URL/access/api/v1/projects/${STATE_PROJECT}")

if [ "$STATUS" = "200" ]; then
  echo "OK: State project '${STATE_PROJECT}' already exists"
elif [ "$STATUS" = "404" ]; then
  echo "Creating state project '${STATE_PROJECT}'..."
  curl -sf -X POST "$JFROG_URL/access/api/v1/projects" \
    -H "Authorization: Bearer $JFROG_ACCESS_TOKEN" \
    -H "Content-Type: application/json" \
    -d '{
      "project_key": "'"${STATE_PROJECT}"'",
      "display_name": "System Configuration",
      "description": "Internal system configuration and manifest storage. Access restricted to platform admins only.",
      "admin_privileges": {
        "manage_members": false,
        "manage_resources": false,
        "index_resources": false
      }
    }'
  echo "OK: State project '${STATE_PROJECT}' created"
else
  echo "WARN: Unexpected status $STATUS checking state project"
fi
```

**Access restriction**: The project is created with all `admin_privileges` set to `false`. This means project-level admins cannot manage members or resources -- only platform admins (using the platform admin token) can read from or write to this project and its repositories.

#### A2. Verify no unexpected members

If the project already exists, check that no non-admin members have been added:

```bash
USERS=$(curl -s -H "Authorization: Bearer $JFROG_ACCESS_TOKEN" \
  "$JFROG_URL/access/api/v1/projects/${STATE_PROJECT}/users" | jq 'length')
GROUPS=$(curl -s -H "Authorization: Bearer $JFROG_ACCESS_TOKEN" \
  "$JFROG_URL/access/api/v1/projects/${STATE_PROJECT}/groups" | jq 'length')

if [ "$USERS" -gt 0 ] || [ "$GROUPS" -gt 0 ]; then
  echo "WARNING: The state project '${STATE_PROJECT}' has $USERS user(s) and $GROUPS group(s) assigned."
  echo "This project should only be accessible via platform admin token."
  echo "Consider removing non-admin members from the project."
fi
```

#### A3. Check/create the repository

```bash
STATUS=$(curl -s -o /dev/null -w '%{http_code}' \
  -H "Authorization: Bearer $JFROG_ACCESS_TOKEN" \
  "$JFROG_URL/artifactory/api/repositories/${STATE_REPO}")

if [ "$STATUS" = "200" ]; then
  echo "OK: State repository '${STATE_REPO}' already exists"
elif [ "$STATUS" = "404" ]; then
  echo "Creating state repository '${STATE_REPO}'..."
  curl -sf -X PUT "$JFROG_URL/artifactory/api/repositories/${STATE_REPO}" \
    -H "Authorization: Bearer $JFROG_ACCESS_TOKEN" \
    -H "Content-Type: application/json" \
    -d '{
      "key": "'"${STATE_REPO}"'",
      "rclass": "local",
      "packageType": "generic",
      "projectKey": "'"${STATE_PROJECT}"'",
      "description": "Stores onboarding manifests and system configuration. Platform admin access only."
    }'
  echo "OK: State repository '${STATE_REPO}' created"
else
  echo "WARN: Unexpected status $STATUS checking state repo"
fi
```

Treat 409 (already exists) as success for both project and repository creation.

### Operation B: List and Download Existing Manifests (Artifactory)

Run with `required_permissions: ["full_network"]`.

#### B1. List manifest snapshots

```bash
CHILDREN=$(curl -s -H "Authorization: Bearer $JFROG_ACCESS_TOKEN" \
  "$JFROG_URL/artifactory/api/storage/${STATE_REPO}/" \
  | jq -r '[.children[]? | select(.folder==true) | .uri] | sort')

MANIFEST_COUNT=$(echo "$CHILDREN" | jq 'length')
echo "Found $MANIFEST_COUNT manifest snapshot(s)"
```

#### B2. Get the latest manifest

Sort timestamp folders lexicographically (ISO-8601 sorts naturally) and download the most recent:

```bash
LATEST_FOLDER=$(curl -s -H "Authorization: Bearer $JFROG_ACCESS_TOKEN" \
  "$JFROG_URL/artifactory/api/storage/${STATE_REPO}/" \
  | jq -r '[.children[]? | select(.folder==true) | .uri] | sort | last')

if [ "$LATEST_FOLDER" != "null" ] && [ -n "$LATEST_FOLDER" ]; then
  echo "Latest manifest folder: $LATEST_FOLDER"
  curl -s -H "Authorization: Bearer $JFROG_ACCESS_TOKEN" \
    "$JFROG_URL/artifactory/${STATE_REPO}${LATEST_FOLDER}/jfrog-configuration-manifest.yaml" \
    -o /tmp/latest-manifest.yaml
  echo "Downloaded to /tmp/latest-manifest.yaml"
else
  echo "No manifests found in '${STATE_REPO}' repository"
fi
```

#### B3. List all snapshots with timestamps

```bash
curl -s -H "Authorization: Bearer $JFROG_ACCESS_TOKEN" \
  "$JFROG_URL/artifactory/api/storage/${STATE_REPO}/" \
  | jq -r '.children[]? | select(.folder==true) | .uri | ltrimstr("/")'
```

### Operation C: Upload Manifest (Artifactory)

Run with `required_permissions: ["full_network"]`.

```bash
TIMESTAMP=$(date -u +"%Y-%m-%dT%H-%M-%SZ")
curl -sf -X PUT \
  "$JFROG_URL/artifactory/${STATE_REPO}/${TIMESTAMP}/jfrog-configuration-manifest.yaml" \
  -H "Authorization: Bearer $JFROG_ACCESS_TOKEN" \
  -H "Content-Type: application/x-yaml" \
  -T "$MANIFEST_FILE"

echo "Manifest uploaded to: ${STATE_REPO}/${TIMESTAMP}/jfrog-configuration-manifest.yaml"
```

Where `$MANIFEST_FILE` is the path to the final manifest YAML file (e.g., `./jfrog-manifest.yaml`).

---

## Git Backend Operations

Use these when `state.destination` = `git`.

### Operation D: Verify Git Repo Accessible

Run with `required_permissions: ["all"]`.

```bash
GITHUB_URL="https://${GITHUB_HOST}/${STATE_GIT_REPO}.git"
git ls-remote "$GITHUB_URL" HEAD 2>/dev/null
if [ $? -ne 0 ]; then
  echo "ERROR: Cannot access git repository: $GITHUB_URL"
  echo "Check that the repo exists and your git credentials are configured."
  exit 1
fi
echo "OK: Git repository '$STATE_GIT_REPO' is accessible"
```

### Operation E: List and Download Existing Manifests (Git)

Run with `required_permissions: ["all"]`.

#### E1. Shallow clone and list snapshots

```bash
TMPDIR=$(mktemp -d)
GITHUB_URL="https://${GITHUB_HOST}/${STATE_GIT_REPO}.git"
git clone --depth 1 --branch "$STATE_GIT_BRANCH" "$GITHUB_URL" "$TMPDIR/state-repo" 2>/dev/null

# Normalize path: ensure it ends with / if non-empty
MANIFEST_DIR="${TMPDIR}/state-repo"
if [ -n "$STATE_GIT_PATH" ] && [ "$STATE_GIT_PATH" != "/" ]; then
  MANIFEST_DIR="${MANIFEST_DIR}/${STATE_GIT_PATH}"
fi

# List timestamp folders (if any exist)
if [ -d "$MANIFEST_DIR" ]; then
  SNAPSHOTS=$(ls -d "$MANIFEST_DIR"/????-??-??T??-??-??Z 2>/dev/null | sort)
  MANIFEST_COUNT=$(echo "$SNAPSHOTS" | grep -c . 2>/dev/null || echo 0)
  echo "Found $MANIFEST_COUNT manifest snapshot(s) in git"
else
  MANIFEST_COUNT=0
  echo "No manifest directory found in git repo at path: $STATE_GIT_PATH"
fi
```

#### E2. Get the latest manifest

```bash
if [ "$MANIFEST_COUNT" -gt 0 ]; then
  LATEST=$(echo "$SNAPSHOTS" | tail -1)
  if [ -f "$LATEST/jfrog-configuration-manifest.yaml" ]; then
    cp "$LATEST/jfrog-configuration-manifest.yaml" /tmp/latest-manifest.yaml
    echo "Downloaded latest manifest to /tmp/latest-manifest.yaml"
  else
    echo "WARNING: Latest snapshot folder exists but manifest file is missing"
  fi
fi
```

#### E3. Cleanup

```bash
rm -rf "$TMPDIR"
```

### Operation F: Upload Manifest (Git)

Run with `required_permissions: ["all"]`.

Clone, add the manifest, commit, and push:

```bash
TMPDIR=$(mktemp -d)
GITHUB_URL="https://${GITHUB_HOST}/${STATE_GIT_REPO}.git"
git clone --depth 1 --branch "$STATE_GIT_BRANCH" "$GITHUB_URL" "$TMPDIR/state-repo" 2>/dev/null

TIMESTAMP=$(date -u +"%Y-%m-%dT%H-%M-%SZ")

# Build the target directory
TARGET_DIR="${TMPDIR}/state-repo"
if [ -n "$STATE_GIT_PATH" ] && [ "$STATE_GIT_PATH" != "/" ]; then
  TARGET_DIR="${TARGET_DIR}/${STATE_GIT_PATH}"
fi
TARGET_DIR="${TARGET_DIR}/${TIMESTAMP}"
mkdir -p "$TARGET_DIR"

# Copy the manifest
cp "$MANIFEST_FILE" "${TARGET_DIR}/jfrog-configuration-manifest.yaml"

# Commit and push
cd "$TMPDIR/state-repo"
git add -A
git commit -m "Add onboarding manifest snapshot ${TIMESTAMP}"
git push origin "$STATE_GIT_BRANCH"

echo "Manifest pushed to: ${STATE_GIT_REPO} @ ${STATE_GIT_BRANCH}:${STATE_GIT_PATH}/${TIMESTAMP}/jfrog-configuration-manifest.yaml"

# Cleanup
cd /
rm -rf "$TMPDIR"
```

---

## Error Handling

- **409 Conflict**: Project or repo already exists -- treat as success (Artifactory)
- **403 Forbidden**: Token lacks platform admin privileges -- this should have been caught by prerequisite checks; report to user (Artifactory)
- **404 Not Found** on list/download: No manifests exist yet -- not an error, proceed normally
- **Git push failure**: Warn the user, suggest checking credentials and branch protection rules
- If upload/push fails, warn the user but do not abort the overall onboarding (manifests are a convenience, not a hard requirement)

## Usage in the Orchestration Skill

The orchestration skill (`jfrog-project-onboarding`) calls this skill at two points:

1. **Pre-flight (Step 0)**: Read `state.destination` from the manifest. For `artifactory`: call Operation A + B to ensure the repo exists and check for prior manifests. For `git`: call Operation D + E to verify the repo and check for prior manifests. If found, alert the user and offer to retrieve the latest.
2. **Post-completion (final step)**: For `artifactory`: call Operation C to upload. For `git`: call Operation F to commit and push.
