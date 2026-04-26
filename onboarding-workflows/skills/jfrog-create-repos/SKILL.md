---
name: jfrog-create-repos
description: Create Artifactory repositories (local, remote, virtual) for npm, Maven, PyPI, Go, Docker, and Helm ecosystems within a JFrog project. Supports ecosystem-based auto-generation, explicit custom repository definitions, or a smart merge of both. Use when the user needs to set up Artifactory repos, create package repositories, or configure artifact storage for a project.
---

# JFrog Create Repositories

Prefer **`jf api`** ([../../../platform-features/skills/jfrog-cli/jf-api-patterns.md](../../../platform-features/skills/jfrog-cli/jf-api-patterns.md)) after `jf config`; **`curl`** snippets are **fallback** when the CLI is unavailable.

Creates repositories scoped to a JFrog project. Supports three modes:
1. **Ecosystem-only** -- auto-generates standard trios (local + remote + virtual) per ecosystem
2. **Repositories-only** -- creates exactly the repos listed in custom definitions
3. **Both (smart merge)** -- generates ecosystem trios, then applies custom overrides and additions

## Inputs

- `project_key` -- the JFrog project key (must already exist)
- `ecosystems` -- (optional) list from: `npm`, `maven`, `pip`, `go`, `docker`, `helm`
- `repositories` -- (optional) list of custom repository definitions from the manifest (see schema in `templates/manifest-template.yaml`)
- `xray_enabled` -- boolean, resolved by the orchestration skill (per-project override or global default). When `true`, Xray indexing is enabled on local and remote repos and `{{XRAY_INDEX}}` in templates is set to `true`. When `false`, indexing is skipped and `{{XRAY_INDEX}}` is set to `false`.
- `curation_enabled` -- boolean, resolved by the orchestration skill (per-project override or global default). When `true`, Curation is activated on remote repos after creation.
- `naming_pattern` -- (optional) object from `detect-existing-patterns` skill that controls how repo names are generated. When not provided, the standard pattern is used. See **Dynamic Naming** below.

At least one of `ecosystems` or `repositories` must be provided. If neither is set, skip repo creation for this project.

## Repository Naming

### Standard Pattern (default)

The standard naming convention, used when `naming_pattern` is not provided:

| Ecosystem | Local | Remote | Virtual |
|-----------|-------|--------|---------|
| npm | `{key}-npm-local` | `{key}-npm-remote` | `{key}-npm` |
| maven | `{key}-maven-local` | `{key}-maven-remote` | `{key}-maven` |
| pip | `{key}-pypi-local` | `{key}-pypi-remote` | `{key}-pypi` |
| go | `{key}-go-local` | `{key}-go-remote` | `{key}-go` |
| docker | `{key}-docker-local` | `{key}-docker-remote` | `{key}-docker` |
| helm | `{key}-helm-local` | `{key}-helm-remote` | `{key}-helm` |

### Dynamic Naming (from detected patterns)

When `naming_pattern` is provided, repo names are generated dynamically using its fields:

| Field | Description | Standard default |
|-------|-------------|-----------------|
| `separator` | Character between name components | `-` |
| `virtual_suffix` | Type label for virtual repos; empty = no suffix | `""` |
| `type_map` | Maps logical types to name tokens | `{"local": "local", "remote": "remote"}` |
| `eco_map` | Maps manifest ecosystem names to repo name tokens (only non-identity entries) | `{"pip": "pypi"}` |

#### Name generation logic

```bash
SEP="${NAMING_SEPARATOR:--}"

# Map ecosystem name to repo name token
ECO_TOKEN="$ECOSYSTEM"
case "$ECOSYSTEM" in
  pip) ECO_TOKEN="${ECO_MAP_PIP:-pypi}" ;;
  # Add additional eco_map entries here if detected
esac

# Local repo key
LOCAL_TYPE="${TYPE_MAP_LOCAL:-local}"
LOCAL_KEY="${PROJECT_KEY}${SEP}${ECO_TOKEN}${SEP}${LOCAL_TYPE}"

# Remote repo key
REMOTE_TYPE="${TYPE_MAP_REMOTE:-remote}"
REMOTE_KEY="${PROJECT_KEY}${SEP}${ECO_TOKEN}${SEP}${REMOTE_TYPE}"

# Virtual repo key
VIRTUAL_SUFFIX="${NAMING_VIRTUAL_SUFFIX:-}"
if [ -z "$VIRTUAL_SUFFIX" ]; then
  VIRTUAL_KEY="${PROJECT_KEY}${SEP}${ECO_TOKEN}"
else
  VIRTUAL_KEY="${PROJECT_KEY}${SEP}${ECO_TOKEN}${SEP}${VIRTUAL_SUFFIX}"
fi
```

When `naming_pattern` is not provided, the logic above produces the same names as the standard pattern table (separator `-`, no virtual suffix, pip -> pypi).

**Important**: Custom repos defined in the `repositories` list always use their explicit `key` values, regardless of `naming_pattern`. Dynamic naming only applies to ecosystem-generated trios.

## Smart Merge Logic (ecosystems + repositories)

When both `ecosystems` and `repositories` inputs are provided, build a **merged repo list** before creating anything:

### Step A: Generate ecosystem repos

For each ecosystem, generate the three repos (local, remote, virtual) using the **Dynamic Naming** logic above (or the standard pattern if `naming_pattern` is not provided). Build their JSON payloads from the templates. Store them in a map keyed by the generated repo key.

### Step B: Apply custom overrides and additions

Iterate through the `repositories` list:

1. **Override** -- if a custom repo's `key` matches an ecosystem-generated key, merge the custom fields into the ecosystem-generated payload. Custom fields take precedence. For example, a custom entry for `myproj-npm-local` with `description: "Custom desc"` and `xray_index: false` overrides those fields while keeping the rest from the template.
2. **Addition** -- if the custom repo's `key` does not match any ecosystem-generated key, add it as a new entry.

### Step C: Validate virtual repo references

For each virtual repo (ecosystem-generated or custom), check that every entry in `aggregated_repos` refers to a repo key that exists in the merged list. If any reference is missing, **abort and report the invalid reference** before creating any repos.

### Step D: Determine creation order

Sort the merged list for creation: **remote** repos first, then **local** repos, then **virtual** repos. This ensures virtual repos can reference already-created repos.

### Custom Repository JSON Payload

For custom repos (those not derived from ecosystem templates), build the JSON payload inline from manifest fields:

```bash
# Example: custom local repo
cat <<REPOEOF
{
  "key": "${REPO_KEY}",
  "rclass": "${REPO_TYPE}",
  "packageType": "${PACKAGE_TYPE}",
  "projectKey": "${PROJECT_KEY}",
  "description": "${DESCRIPTION}",
  "xrayIndex": ${XRAY_INDEX}
}
REPOEOF
```

For custom **remote** repos, also include `"url": "${URL}"`.

For custom **virtual** repos, include `"repositories"` (the aggregated list) and optionally `"defaultDeploymentRepo"`:

```bash
cat <<REPOEOF
{
  "key": "${REPO_KEY}",
  "rclass": "virtual",
  "packageType": "${PACKAGE_TYPE}",
  "projectKey": "${PROJECT_KEY}",
  "description": "${DESCRIPTION}",
  "repositories": ["repo-a", "repo-b"],
  "defaultDeploymentRepo": "${DEFAULT_DEPLOY_REPO}"
}
REPOEOF
```

Per-repo `xray_index` in custom definitions: if the custom repo specifies `xray_index`, use that value. Otherwise, inherit from the resolved `xray_enabled` input (project-level or global).

## Workflow

### 0. Load credentials

```bash
# Load .env if JFROG_URL or JFROG_ACCESS_TOKEN are not already set
if [ -z "$JFROG_URL" ] || [ -z "$JFROG_ACCESS_TOKEN" ]; then
  if [ -f .env ]; then
    set -a; source .env; set +a
  fi
fi
```

### 0b. Verify project exists (MANDATORY)

Before creating any repositories, verify the target project exists. If the project does not exist, Artifactory silently ignores the `projectKey` in the repo payload and creates repos that are **not assigned** to any project. This makes them invisible to project-scoped queries (`?project={key}`) and breaks deletion, reconciliation, and other project-aware operations.

```bash
jf api "/access/api/v1/projects/$PROJECT_KEY" >/tmp/jf-cr-proj.json 2>/tmp/jf-cr-proj.code
HTTP_CODE=$(tr -d '\r\n' < /tmp/jf-cr-proj.code)

if [ "$HTTP_CODE" != "200" ]; then
  echo "ABORT: Project '$PROJECT_KEY' does not exist (HTTP $HTTP_CODE)."
  echo "Create the project first using the jfrog-provision-project skill."
  exit 1
fi
```

**Do not proceed with repo creation if this check fails.**

Build the merged repo list (see Smart Merge Logic above), then create repos in order: **remote** first, then **local**, then **virtual**.

For each repo in the merged list:

### 1. Create Repository

**Ecosystem-generated repos** (from templates):

```bash
# Generate REPO_KEY using the Dynamic Naming logic (see above).
# Example with standard pattern:
#   REPO_KEY="${PROJECT_KEY}-${ECO_TOKEN}-${LOCAL_TYPE}"
# Example with detected pattern (separator="_", virtual_suffix="virtual"):
#   REPO_KEY="${PROJECT_KEY}_${ECO_TOKEN}_${LOCAL_TYPE}"

PAYLOAD=$(sed "s/{{PROJECT_KEY}}/$PROJECT_KEY/g; s/{{REPO_KEY}}/$REPO_KEY/g; s/{{XRAY_INDEX}}/$XRAY_INDEX/g" \
  templates/repos/${ECOSYSTEM}-${TYPE}.json)
jf api "/artifactory/api/repositories/$REPO_KEY" -X PUT \
  -H "Content-Type: application/json" \
  -d "$PAYLOAD"
```

**Custom repos** (from `repositories` list, no matching template):

```bash
# Build JSON payload inline from manifest fields (see Custom Repository JSON Payload above)
jf api "/artifactory/api/repositories/$REPO_KEY" -X PUT \
  -H "Content-Type: application/json" \
  -d "$CUSTOM_JSON_PAYLOAD"
```

**Overridden repos** (ecosystem-generated + custom fields merged):

Start from the ecosystem template JSON, then overlay custom fields using `jq`:

```bash
PAYLOAD=$(sed "s/{{PROJECT_KEY}}/$PROJECT_KEY/g; s/{{REPO_KEY}}/$REPO_KEY/g; s/{{XRAY_INDEX}}/$XRAY_INDEX/g" \
  templates/repos/${ECOSYSTEM}-${TYPE}.json)
# Merge custom overrides
PAYLOAD=$(echo "$PAYLOAD" | jq '. + {"description": "Custom desc", "xrayIndex": false}')
jf api "/artifactory/api/repositories/$REPO_KEY" -X PUT \
  -H "Content-Type: application/json" \
  -d "$PAYLOAD"
```

### 2. Verify

```bash
jf api "/artifactory/api/repositories/$REPO_KEY" | jq '.key, .type, .packageType'
```

## Template Substitution

Before sending each JSON template, replace these placeholders:
- `{{PROJECT_KEY}}` -- the project key
- `{{REPO_KEY}}` -- the full repository key (e.g., `myproj-npm-local`)
- `{{XRAY_INDEX}}` -- `true` or `false` based on the resolved `xray_enabled` input

Use `sed` or string substitution in the shell:
```bash
# Determine XRAY_INDEX value from the resolved xray_enabled input
XRAY_INDEX="true"   # or "false" based on xray_enabled

sed "s/{{PROJECT_KEY}}/$PROJECT_KEY/g; s/{{REPO_KEY}}/$REPO_KEY/g; s/{{XRAY_INDEX}}/$XRAY_INDEX/g" \
  templates/repos/npm-local.json
```

## 5. Xray Indexing (Conditional)

**Skip this step entirely if `xray_enabled` is `false`.** When `xray_enabled` is `false`, the `{{XRAY_INDEX}}` placeholder was already set to `false` in the repo templates, so repos are created without Xray indexing and no further action is needed.

When `xray_enabled` is `true`, after all repositories for a project are created, check if Xray is available on the platform and add repos to the indexed resources.

### Check Xray Availability and Get Binary Manager ID

All API calls below follow the **Safe API Call Pattern** (see `jfrog-platform` rule) -- capture HTTP status and body separately, check status before parsing with jq.

```bash
jf api /artifactory/api/xrayRepo/getIntegrationConfig \
  >/tmp/xray-config.json 2>/tmp/xray-config.code
HTTP_CODE=$(tr -d '\r\n' < /tmp/xray-config.code)

if [ "$HTTP_CODE" = "200" ]; then
  XRAY_AVAILABLE=$(jq -r '.xrayEnabled' /tmp/xray-config.json)
else
  XRAY_AVAILABLE="false"
fi
```

- `XRAY_AVAILABLE="true"` -- Xray is available and enabled on the platform
- `XRAY_AVAILABLE="false"` or null/empty -- Xray is not available; skip indexing and warn the user

If Xray is available, discover the binary manager ID (required for the indexing API):

```bash
HTTP_CODE=$( (jf api "/xray/api/v1/binMgr" >/tmp/xray-binmgr.json 2>/tmp/xray-binmgr.code) ; tr -d '\r\n' < /tmp/xray-binmgr.code )

if [ "$HTTP_CODE" = "200" ]; then
  BIN_MGR_ID=$(jq -r '.[0].bin_mgr_id // "default"' /tmp/xray-binmgr.json)
else
  BIN_MGR_ID="default"
fi
```

**Important**: If `xray_enabled` is `true` in the manifest but Xray is not available on the platform, do **not** abort. Log a warning to the user:
> "Xray indexing was requested but Xray is not available on this platform. Repositories were created without Xray indexing."

### Enable Indexing on Repositories

If Xray is available, enable indexing on all newly created **local** and **remote** repos (not virtual). This includes both ecosystem-generated repos and custom repos from the `repositories` list. For custom repos, only index those whose resolved `xray_index` is `true` (explicit per-repo value, or inherited from `xray_enabled`).

Uses the `PUT /xray/api/v1/binMgr/{id}/repos` API ([docs](https://jfrog.com/help/r/xray-rest-apis/update-repos-indexing-configuration)).

**IMPORTANT**: The `PUT /xray/api/v1/binMgr/{id}/repos` endpoint **replaces** the entire indexed repos list. Sending only the new repos will **remove** all previously indexed repos. Always GET the current list first, merge in new repos (dedup by name), and PUT the combined set. Add a 1-second delay between sequential API calls to avoid triggering platform rate limits.

```bash
# Step 1: GET the existing indexed repos (safe pattern)
HTTP_CODE=$( (jf api "/xray/api/v1/binMgr/$BIN_MGR_ID/repos" >/tmp/xray-current.json 2>/tmp/xray-current.code) ; tr -d '\r\n' < /tmp/xray-current.code )

if [ "$HTTP_CODE" = "200" ]; then
  EXISTING=$(jq '.indexed_repos // []' /tmp/xray-current.json)
else
  echo "WARN: Could not GET current Xray index (HTTP $HTTP_CODE), using empty list"
  EXISTING="[]"
fi

# Step 2: Build the JSON array of NEW repos to add
# Use known values from the ecosystem -- do NOT make extra API calls to look up rclass/packageType
NEW_REPOS='[
  {"name": "'${PROJECT_KEY}'-npm-local", "type": "local", "pkg_type": "npm"},
  {"name": "'${PROJECT_KEY}'-npm-remote", "type": "remote", "pkg_type": "npm"},
  {"name": "myproject-thirdparty-remote", "type": "remote", "pkg_type": "generic"}
]'

# Step 3: Merge existing + new, deduplicate by name
MERGED=$(echo "$EXISTING" "$NEW_REPOS" \
  | jq -s 'add | group_by(.name) | map(.[0])')

# Step 4: PUT the merged list (safe pattern)
echo "{\"indexed_repos\": $MERGED}" >/tmp/xray-merged-create-repos.json
jf api "/xray/api/v1/binMgr/$BIN_MGR_ID/repos" -X PUT -H "Content-Type: application/json" \
  --input /tmp/xray-merged-create-repos.json >/tmp/xray-put-resp.json 2>/tmp/xray-put-resp.code
HTTP_CODE=$(tr -d '\r\n' < /tmp/xray-put-resp.code)

if [ "$HTTP_CODE" = "200" ]; then
  echo "OK: Xray index updated"
else
  echo "ERROR: Xray index PUT failed (HTTP $HTTP_CODE)"
  cat /tmp/xray-put-resp.json
fi
```

Only include repos that were actually created and have Xray indexing enabled. Virtual repos do not need indexing -- Xray scans artifacts in local and remote repos.

Report the Xray indexing result to the user:
- If enabled: "Xray indexing enabled on {N} repositories"
- If not available: "Xray is not available on this platform; skipping indexing"

## 6. Curation (Conditional)

**Skip this step entirely if `curation_enabled` is `false`.** Curation only applies to **remote** repositories.

When `curation_enabled` is `true`, after all repositories for a project are created, check if Curation is available on the platform and enable it on remote repos.

### Check Curation Availability

```bash
jf api /curation/api/v1/system/status >/dev/null 2>/tmp/curation-status.code
CURATION_STATUS=$(tr -d '\r\n' < /tmp/curation-status.code)
```

- HTTP 200 -- Curation is available
- Any other code -- Curation is not available; skip and warn the user

**Important**: If `curation_enabled` is `true` in the manifest but Curation is not available on the platform, do **not** abort. Log a warning to the user:
> "Curation was requested but is not available on this platform. Repositories were created without Curation."

### Enable Curation on Remote Repositories

If Curation is available, enable it on each newly created **remote** repository -- both ecosystem-generated and custom remote repos:

```bash
# For each remote repo (ecosystem-generated or custom):
REPO_KEY="${REMOTE_REPO_KEY}"
jf api "/curation/api/v1/repos/${REPO_KEY}" -X PUT \
  -H "Content-Type: application/json" \
  -d '{"curated": true}'
```

Report the Curation result to the user:
- If enabled: "Curation enabled on {N} remote repositories"
- If not available: "Curation is not available on this platform; skipping"

## Error Handling

- **409 Conflict**: Repo already exists -- skip and continue
- **400 Bad Request**: Invalid configuration -- check JSON template
- After all repos are created, report which succeeded and which were skipped

## Official Documentation

For full API details and upstream URLs, see [reference.md](reference.md). For detailed npm setup, see [npm.md](npm.md). For detailed Docker setup, see [docker.md](docker.md).

- [Artifactory REST APIs](https://jfrog.com/help/r/jfrog-rest-apis/artifactory-rest-apis)
- [Repository Management](https://jfrog.com/help/r/jfrog-artifactory-documentation/repository-management)

## Related skills

For Artifactory repo schema, API reference, and general repository concepts, see **platform-features** (`jfrog-artifactory`).
