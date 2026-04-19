---
name: jfrog-reconcile-manifest
description: Reconcile JFrog Platform state with a desired-state manifest. Reads current configuration, computes a diff, presents changes for approval, and applies only the delta. Use when the user wants to update, sync, or reconcile JFrog with manifest changes.
---

# JFrog Reconcile Manifest

Prefer **`jf api`** ([../../../platform-features/skills/jfrog-cli/jf-api-patterns.md](../../../platform-features/skills/jfrog-cli/jf-api-patterns.md)) after `jf config`; **`curl`** remains valid **fallback** for the same paths.

Given a manifest YAML describing the desired state, compare it against the current JFrog Platform state and apply only the differences -- after user approval.

## Inputs

- `manifest` -- the desired-state manifest YAML, **explicitly provided by the user** (file path or parsed structure), following the schema in `templates/manifest-template.yaml`. This must be a path the user gave directly -- never auto-discover or use locally found manifest files.
- `baseline` -- (optional) a previously stored manifest YAML used as the baseline for comparison. If provided by the caller (e.g., the orchestration skill already downloaded it from the state backend), skip the retrieval in Phase 0. The baseline must always come from the configured state backend (Artifactory or git) -- never from a locally found file.
- All JFrog credentials (`JFROG_URL`, `JFROG_ACCESS_TOKEN`) must be loaded and validated before invoking this skill (handled by the orchestration skill's prerequisite checks)

## Overview

The reconciliation operates as a **3-way comparison** (similar to `terraform plan`) when a baseline manifest is available, or a 2-way comparison when it is not:

```
Baseline Manifest             Desired State (manifest)    Live State (JFrog APIs)
(last applied state)                  |                         |
        \                             |                         |
         +--- What changed in --------+                         |
              the manifest                                      |
                     \                                         /
                      +------------ Diff Engine --------------+
                                        |
                                 Change Summary
                            (manifest changes + drift)
                                        |
                                  User Approval
                                        |
                                   Apply Delta
```

- **Baseline manifest** = the last manifest that was successfully applied and persisted to the state backend (Artifactory or git). Think of it as the Terraform state file.
- **Desired state** = the new/edited manifest the user wants to apply now.
- **Live state** = the actual current configuration in the JFrog Platform (read from APIs).

When a baseline is available, the diff summary shows:
- **Manifest changes**: what the user intentionally changed (baseline vs. desired)
- **Drift**: what changed in the live platform since the last apply (baseline vs. live)
- **Net actions**: what operations are needed to bring live state to the desired state

When no baseline is available, the skill falls back to a 2-way comparison (desired vs. live), which is the standard behavior.

## Phase 0: Retrieve Baseline Manifest (State File)

Before reading live state, check for a previously stored manifest to use as a baseline. This step is skipped if the caller already provides a `baseline` input.

### 0.1 Determine state backend

```bash
DESTINATION=$(yq -r '.state.destination // "artifactory"' "$MANIFEST_FILE")
```

### 0.2 Ask the user about baseline source

Present the user with a choice (use `AskQuestion`):

> To produce an accurate change plan, I can compare your new manifest against a **baseline** (the last applied manifest stored in your state backend). Should I retrieve it?

Options:
- **Retrieve from state backend** (`<artifactory|git>` -- based on `state.destination`) -- retrieves the latest stored manifest automatically
- **No baseline (skip)** -- proceed with live-only comparison (2-way diff)

**Important**: The baseline must always come from the configured state backend (Artifactory or git). Do not offer or accept locally found files as baselines. Only the user-provided desired-state manifest and the stored state file are used in the comparison.

### 0.3 Retrieve from state backend

If the user chooses the state backend option, use the `jfrog-system-config-repo` skill:

#### Artifactory backend (`state.destination = artifactory`)

Run with `required_permissions: ["full_network"]`.

```bash
STATE_PROJECT=$(yq -r '.state.artifactory.project // "system"' "$MANIFEST_FILE")
STATE_REPO=$(yq -r '.state.artifactory.repository // "system-configuration"' "$MANIFEST_FILE")

# Check if the state repo exists
jf api "/artifactory/api/repositories/${STATE_REPO}" >/tmp/rec-state-repo.json 2>/tmp/rec-state-repo.code
STATUS=$(tr -d '\r\n' < /tmp/rec-state-repo.code)

if [ "$STATUS" != "200" ]; then
  echo "INFO: State repository '${STATE_REPO}' does not exist. No baseline available."
  echo "Proceeding with live-only comparison."
  BASELINE_FILE=""
else
  # Use Operation B from jfrog-system-config-repo to get the latest manifest
  jf api "/artifactory/api/storage/${STATE_REPO}/" >/tmp/rec-storage.json 2>/dev/null
  LATEST_FOLDER=$(jq -r '[.children[]? | select(.folder==true) | .uri] | sort | last' /tmp/rec-storage.json)

  if [ "$LATEST_FOLDER" != "null" ] && [ -n "$LATEST_FOLDER" ]; then
    jf api "/artifactory/${STATE_REPO}${LATEST_FOLDER}/jfrog-configuration-manifest.yaml" \
      >/tmp/baseline-manifest.yaml 2>/dev/null
    echo "OK: Retrieved baseline manifest from ${STATE_REPO}${LATEST_FOLDER}"
    BASELINE_FILE="/tmp/baseline-manifest.yaml"
  else
    echo "INFO: No manifest snapshots found in '${STATE_REPO}'. No baseline available."
    BASELINE_FILE=""
  fi
fi
```

#### Git backend (`state.destination = git`)

Run with `required_permissions: ["all"]`.

Use Operation E from `jfrog-system-config-repo` to clone the repo and retrieve the latest manifest snapshot. If found, save to `/tmp/baseline-manifest.yaml`.

### 0.4 Baseline loaded summary

After retrieval (or skip), report to the user:

- **Baseline found**: "Using baseline manifest from `<source>` (timestamp: `<ts>`). Changes will be shown as a 3-way comparison."
- **No baseline**: "No baseline manifest available. Changes will be computed against live JFrog state only (2-way comparison)."

Store the baseline (if any) as `BASELINE_FILE` for use in Phase 2.

## Phase 1: Read Current State

For each project listed in the manifest, query the JFrog Platform to discover what currently exists. All API calls run with `required_permissions: ["full_network"]`.

**IMPORTANT**: Prefer **`jf api`** ([../../../platform-features/skills/jfrog-cli/jf-api-patterns.md](../../../platform-features/skills/jfrog-cli/jf-api-patterns.md)). Follow the **Safe API Call Pattern** from the `jfrog-platform` rule -- never pipe API stdout directly to `jq`. Capture HTTP status and body separately (`jf api` writes status to stderr), check the status before parsing. Add `sleep 1` between calls in loops to avoid rate limiting.

### 1.1 Projects

```bash
STATUS=$( (jf api "/access/api/v1/projects/$PROJECT_KEY" >/tmp/project-$PROJECT_KEY.json 2>/tmp/project-$PROJECT_KEY.code) ; tr -d '\r\n' < /tmp/project-$PROJECT_KEY.code )
# 200 = exists (details in temp file), 404 = does not exist
if [ "$STATUS" = "200" ]; then
  jq . /tmp/project-$PROJECT_KEY.json
fi
```

### 1.2 Repositories

```bash
HTTP_CODE=$( (jf api "/artifactory/api/repositories?project=$PROJECT_KEY" >/tmp/repos-$PROJECT_KEY.json 2>/tmp/repos-$PROJECT_KEY.code) ; tr -d '\r\n' < /tmp/repos-$PROJECT_KEY.code )

if [ "$HTTP_CODE" = "200" ]; then
  REPO_KEYS=$(jq -r '.[].key' /tmp/repos-$PROJECT_KEY.json)
else
  echo "ERROR: Failed to list repos (HTTP $HTTP_CODE)"
fi

# For each repo, get details including xrayIndex (with rate-limit protection)
for REPO_KEY in $REPO_KEYS; do
  HTTP_CODE=$( (jf api "/artifactory/api/repositories/$REPO_KEY" >/tmp/repo-$REPO_KEY.json 2>/tmp/repo-$REPO_KEY.code) ; tr -d '\r\n' < /tmp/repo-$REPO_KEY.code )
  if [ "$HTTP_CODE" = "200" ]; then
    jq '{key, rclass, packageType, xrayIndex}' /tmp/repo-$REPO_KEY.json
  fi
  sleep 1
done
```

### 1.3 Members

```bash
HTTP_CODE=$( (jf api "/access/api/v1/projects/$PROJECT_KEY/users" >/tmp/users-$PROJECT_KEY.json 2>/tmp/users-$PROJECT_KEY.code) ; tr -d '\r\n' < /tmp/users-$PROJECT_KEY.code )
if [ "$HTTP_CODE" = "200" ]; then
  CURRENT_USERS=$(cat /tmp/users-$PROJECT_KEY.json)
fi

HTTP_CODE=$( (jf api "/access/api/v1/projects/$PROJECT_KEY/groups" >/tmp/groups-$PROJECT_KEY.json 2>/tmp/groups-$PROJECT_KEY.code) ; tr -d '\r\n' < /tmp/groups-$PROJECT_KEY.code )
if [ "$HTTP_CODE" = "200" ]; then
  CURRENT_GROUPS=$(cat /tmp/groups-$PROJECT_KEY.json)
fi
```

### 1.4 OIDC (if `github.oidc_setup: true`)

```bash
HTTP_CODE=$( (jf api "/access/api/v1/oidc" >/tmp/oidc-providers.json 2>/tmp/oidc-providers.code) ; tr -d '\r\n' < /tmp/oidc-providers.code )

if [ "$HTTP_CODE" = "200" ]; then
  for PROVIDER_NAME in $(jq -r '.[].name' /tmp/oidc-providers.json); do
    jf api "/access/api/v1/oidc/${PROVIDER_NAME}/identity_mappings" \
      >/tmp/oidc-mappings-$PROVIDER_NAME.json 2>/tmp/oidc-mappings-$PROVIDER_NAME.code
    sleep 1
  done
fi
```

### 1.5 Xray Indexing Status

```bash
HTTP_CODE=$( (jf api "/xray/api/v1/binMgr" >/tmp/xray-binmgr.json 2>/tmp/xray-binmgr.code) ; tr -d '\r\n' < /tmp/xray-binmgr.code )

if [ "$HTTP_CODE" = "200" ]; then
  BIN_MGR_ID=$(jq -r '.[0].bin_mgr_id // "default"' /tmp/xray-binmgr.json)
else
  BIN_MGR_ID="default"
fi

HTTP_CODE=$( (jf api "/xray/api/v1/binMgr/$BIN_MGR_ID/repos" >/tmp/xray-indexed.json 2>/tmp/xray-indexed.code) ; tr -d '\r\n' < /tmp/xray-indexed.code )

if [ "$HTTP_CODE" = "200" ]; then
  INDEXED_REPOS=$(jq '.indexed_repos' /tmp/xray-indexed.json)
else
  echo "WARN: Could not retrieve Xray indexed repos (HTTP $HTTP_CODE)"
  INDEXED_REPOS="[]"
fi
```

### 1.6 Curation Status

```bash
# For each remote repo, check curation status (with rate-limit protection)
HTTP_CODE=$( (jf api "/curation/api/v1/repos/${REPO_KEY}" >/tmp/curation-$REPO_KEY.json 2>/tmp/curation-$REPO_KEY.code) ; tr -d '\r\n' < /tmp/curation-$REPO_KEY.code )
if [ "$HTTP_CODE" = "200" ]; then
  CURATED=$(jq -r '.curated // false' /tmp/curation-$REPO_KEY.json)
fi
sleep 1
```

## Phase 2: Compute Diff

Compare the manifest (desired state) against the current state gathered in Phase 1. When a baseline manifest is available (from Phase 0), also compare baseline vs. live to detect **drift** (changes made outside of the manifest workflow).

### Diff modes

| Baseline available? | Comparison | What it shows |
|---------------------|------------|---------------|
| Yes | Baseline → Desired | What the user intentionally changed in the manifest |
| Yes | Baseline → Live | What drifted in the platform since last apply |
| Yes | Desired → Live | What actions are needed (net result) |
| No | Desired → Live | Standard 2-way diff (current behavior) |

The **net actions** (Desired → Live) always determine what gets applied. The baseline comparisons are informational, helping the user understand *why* a change is being made.

Categorize every difference into one of these change types:

### 2.1 Projects

| Current State | Desired State | Change Type |
|---------------|---------------|-------------|
| Does not exist | In manifest | **CREATE** project |
| Exists | In manifest | **NO CHANGE** (project already exists) |
| Exists | Not in manifest | **FLAG** (warn user but do NOT auto-delete) |

### 2.2 Repositories

For each project, build the **desired repo set** by:
1. Generating expected repos from the manifest `ecosystems` list (local + remote + virtual per ecosystem)
2. Applying the `repositories` list (custom definitions): overrides for matching keys, additions for new keys
3. This is the same smart merge logic used by `jfrog-create-repos`

Then compare the desired repo set against current repos:

| Current State | Desired State | Change Type |
|---------------|---------------|-------------|
| Repo does not exist | In desired set (ecosystem or custom) | **CREATE** repo |
| Repo exists, config matches | In desired set | **NO CHANGE** |
| Repo exists, config differs | In desired set with different properties | **UPDATE** repo config (e.g., description, xrayIndex) |
| Repo exists | Not in desired set | **FLAG** (extra repo -- warn but do NOT delete) |

For custom repos being created, use inline JSON payloads (same approach as `jfrog-create-repos`). For overridden repos, merge the custom fields into the existing config.

### 2.3 Xray/Curation Settings

For each existing repo, compare the current `xrayIndex` value against the resolved `xray_enabled` and curation status against `curation_enabled`:

| Setting | Current | Desired | Change Type |
|---------|---------|---------|-------------|
| xrayIndex | `true` | `true` | NO CHANGE |
| xrayIndex | `false` | `true` | **ENABLE** Xray indexing |
| xrayIndex | `true` | `false` | **DISABLE** Xray indexing |
| curated | `false` | `true` | **ENABLE** Curation |
| curated | `true` | `false` | **DISABLE** Curation |

### 2.4 Members

Compare current project members against manifest members:

| Current State | Desired State | Change Type |
|---------------|---------------|-------------|
| User/group not in project | In manifest members | **ADD** member |
| User/group in project with same role | In manifest with same role | **NO CHANGE** |
| User/group in project with different role | In manifest with different role | **UPDATE** role |
| User/group in project | Not in manifest members | **REMOVE** member (flag for user approval) |

### 2.5 OIDC

| Current State | Desired State | Change Type |
|---------------|---------------|-------------|
| No provider | `oidc_setup: true` | **CREATE** provider + mappings |
| Provider exists, mapping missing | Repo in manifest | **CREATE** identity mapping |
| Provider exists, mapping exists | Repo in manifest | **NO CHANGE** |
| Mapping exists | Repo not in manifest | **FLAG** (extra mapping -- warn) |
| Provider exists | `oidc_setup: false` | **FLAG** (warn -- OIDC was previously set up) |

## Phase 3: Present Diff

Display a clear, structured summary of all changes to the user. Group by project and use symbols to indicate change type.

### 3-way presentation (when baseline is available)

When a baseline manifest is available, present the diff in two sections: a **manifest changes** summary (what the user changed) and a **drift** summary (what changed in the platform), followed by the **planned actions** (what will be applied).

```
Reconciliation Plan:
====================

Baseline: system-configuration/2026-02-17T15-30-00Z (Artifactory)

--- Manifest Changes (what you changed) ---

Project "webapp":
  Repositories:
    + ADDED to manifest: go ecosystem (webapp-go-local, webapp-go-remote, webapp-go)
    + ADDED to manifest: webapp-npm-release (custom local/npm)
    ~ CHANGED in manifest: webapp-npm-local (description updated)
  Members:
    + ADDED to manifest: charlie (Developer)
    ~ CHANGED in manifest: alice role (Contributor -> Developer)
    - REMOVED from manifest: bob

Project "newsvc":
  + NEW project added to manifest

--- Drift (changed outside manifest since last apply) ---

Project "webapp":
  Repositories:
    ! webapp-docker-remote: xrayIndex changed (was true, now false) -- modified outside manifest
    ! webapp-legacy-local: exists in JFrog but was never in any manifest
  Members:
    [no drift detected]

--- Planned Actions (what will be applied) ---

Project "webapp" (EXISTS):
  Repositories:
    + CREATE (ecosystem): webapp-go-local, webapp-go-remote, webapp-go (virtual)
    + CREATE (custom): webapp-npm-release (local/npm)
    ~ UPDATE: webapp-npm-local (description changed)
    [no change]: webapp-npm-remote, webapp-npm, webapp-docker-local, webapp-docker-remote, webapp-docker
  Xray:
    ~ ENABLE indexing on: webapp-go-local, webapp-go-remote, webapp-npm-release
  Curation:
    [no change]
  Members:
    + ADD user: charlie (Developer)
    ~ UPDATE role: alice (Contributor -> Developer)
    - REMOVE user: bob (in JFrog but not in manifest)
  OIDC:
    [no change]

Project "newsvc" (NEW):
  + CREATE project
  + CREATE repositories: newsvc-npm-local, newsvc-npm-remote, newsvc-npm
  + ENABLE Xray indexing on: newsvc-npm-local, newsvc-npm-remote
  + ADD members: dev-team (Developer)

Flagged items (require explicit confirmation):
  ! Project "webapp": user "bob" is in JFrog but not in manifest. Remove? (Yes/No)
  ! Project "webapp": repo "webapp-legacy-local" exists but is not in desired repo set. (No action taken -- informational only.)
  ! Project "webapp": repo "webapp-docker-remote" has drifted xrayIndex. The desired state will restore it to true.

Proceed with changes? (Yes / No)
```

### 2-way presentation (no baseline)

When no baseline is available, skip the "Manifest Changes" and "Drift" sections and show only the "Planned Actions" section:

```
Reconciliation Plan:
====================

Baseline: none (comparing desired manifest against live JFrog state)

--- Planned Actions ---

Project "webapp" (EXISTS):
  Repositories:
    + CREATE (ecosystem): webapp-go-local, webapp-go-remote, webapp-go (virtual)
    + CREATE (custom): webapp-npm-release (local/npm)
    ~ UPDATE: webapp-npm-local (description changed)
    [no change]: webapp-npm-remote, webapp-npm, webapp-docker-local, webapp-docker-remote, webapp-docker
  Xray:
    ~ ENABLE indexing on: webapp-go-local, webapp-go-remote, webapp-npm-release
  Curation:
    [no change]
  Members:
    + ADD user: charlie (Developer)
    ~ UPDATE role: alice (Contributor -> Developer)
    - REMOVE user: bob (in JFrog but not in manifest)
  OIDC:
    [no change]

Project "newsvc" (NEW):
  + CREATE project
  + CREATE repositories: newsvc-npm-local, newsvc-npm-remote, newsvc-npm
  + ENABLE Xray indexing on: newsvc-npm-local, newsvc-npm-remote
  + ADD members: dev-team (Developer)

Flagged items (require explicit confirmation):
  ! Project "webapp": user "bob" is in JFrog but not in manifest. Remove? (Yes/No)
  ! Project "webapp": repo "webapp-legacy-local" exists but is not in desired repo set. (No action taken -- informational only.)

Proceed with changes? (Yes / No)
```

### Change type symbols

| Symbol | Meaning |
|--------|---------|
| `+` | Create / Add |
| `~` | Update / Modify |
| `-` | Remove |
| `!` | Flagged -- requires explicit user confirmation |
| `[no change]` | Already matches desired state |

### Deletion policy

- **Projects**: Never auto-delete. Only flag as informational.
- **Repositories**: Never auto-delete. Flag extra repos as informational.
- **Members**: Prompt user for each member removal individually. If user declines, skip the removal.
- **OIDC mappings**: Flag extra mappings as informational. Do not auto-remove.

## Phase 4: Apply Delta

Only proceed after the user explicitly approves the changes. Execute only the delta operations, reusing existing skills:

### 4.1 Create new projects

**Skill**: `jfrog-provision-project` -- for each project marked as CREATE.

### 4.2 Create new / update existing repositories

**Skill**: `jfrog-create-repos` -- pass `ecosystems`, `repositories`, `xray_enabled`, and `curation_enabled` as resolved for the project. The skill handles the smart merge logic and creates/updates repos as needed.

For repos that already exist but need config updates (e.g., changed description, xrayIndex toggle):

```bash
jf api "/artifactory/api/repositories/$REPO_KEY" -X POST \
  -H "Content-Type: application/json" \
  -d "$UPDATED_JSON_PAYLOAD"
```

### 4.3 Update Xray indexing

For repos where Xray indexing needs to change:

**IMPORTANT**: The `PUT /xray/api/v1/binMgr/{id}/repos` endpoint **replaces** the entire indexed repos list. Sending only new repos will **remove** all previously indexed repos from the list. Always GET the current list first, merge in new repos (dedup by name), and PUT the combined set.

**Enable indexing** -- two steps per repo, then a single merged PUT:

Step 1: Set `xrayIndex: true` on each repo's Artifactory config (add a 1-second delay between calls to avoid rate limiting):

```bash
jf api "/artifactory/api/repositories/$REPO_KEY" -X POST \
  -H "Content-Type: application/json" \
  -d '{"xrayIndex": true}'
sleep 1
```

Step 2: After all repo configs are updated, merge new repos into the Xray index:

```bash
# GET existing indexed repos (safe pattern: check status before parsing)
HTTP_CODE=$( (jf api "/xray/api/v1/binMgr/$BIN_MGR_ID/repos" >/tmp/xray-current.json 2>/tmp/xray-current.code) ; tr -d '\r\n' < /tmp/xray-current.code )

if [ "$HTTP_CODE" = "200" ]; then
  EXISTING=$(jq '.indexed_repos // []' /tmp/xray-current.json)
else
  echo "WARN: Could not GET current Xray index (HTTP $HTTP_CODE), using empty list"
  EXISTING="[]"
fi

# Build JSON array of new repos to add (use known values, not extra API lookups)
NEW_REPOS='[{"name":"REPO1","type":"local","pkg_type":"npm"}, ...]'

# Merge: combine existing + new, deduplicate by name
MERGED=$(echo "$EXISTING" "$NEW_REPOS" \
  | jq -s 'add | group_by(.name) | map(.[0])')

# PUT the merged list (write body to file; jf api uses --input for JSON body)
echo "{\"indexed_repos\": $MERGED}" >/tmp/xray-merged.json
jf api "/xray/api/v1/binMgr/$BIN_MGR_ID/repos" -X PUT -H "Content-Type: application/json" \
  --input /tmp/xray-merged.json >/tmp/xray-put-resp.json 2>/tmp/xray-put-resp.code
HTTP_CODE=$(tr -d '\r\n' < /tmp/xray-put-resp.code)

if [ "$HTTP_CODE" = "200" ]; then
  echo "OK: Xray index updated"
else
  echo "ERROR: Xray index PUT failed (HTTP $HTTP_CODE)"
fi
```

**Disable indexing** (update repo config):

```bash
jf api "/artifactory/api/repositories/$REPO_KEY" -X POST \
  -H "Content-Type: application/json" \
  -d '{"xrayIndex": false}'
```

### 4.4 Update Curation

For remote repos where Curation needs to change:

```bash
# Enable
jf api "/curation/api/v1/repos/${REPO_KEY}" -X PUT \
  -H "Content-Type: application/json" \
  -d '{"curated": true}'

# Disable
jf api "/curation/api/v1/repos/${REPO_KEY}" -X PUT \
  -H "Content-Type: application/json" \
  -d '{"curated": false}'
```

### 4.5 Add/update/remove members

**Skill**: `jfrog-manage-members` -- for adding and updating roles.

For removals (only after individual user approval):

```bash
# Remove user from project
jf api "/access/api/v1/projects/$PROJECT_KEY/users/$JFROG_USER_NAME" -X DELETE

# Remove group from project
jf api "/access/api/v1/projects/$PROJECT_KEY/groups/$GROUPNAME" -X DELETE
```

**Fallback:** same paths with `curl -sf -X DELETE` and bearer token.

### 4.6 OIDC changes

**Skill**: `jfrog-oidc-setup` -- for creating new providers and mappings.

### 4.7 GitHub repo configuration

If new ecosystems were added and GitHub repos are configured, the package-manager and CI workflow skills should also be triggered for the new ecosystems:

- **Skill**: `github-configure-package-managers` -- for new ecosystems only
- **Skill**: `github-configure-ci-workflows` -- for new ecosystems only

## Error Handling

- **409 Conflict**: Resource already exists -- treat as success (idempotent)
- **404 Not Found**: Resource does not exist where expected -- include in diff as needing creation
- If any apply operation fails, report the error but continue with remaining changes
- Provide a final summary of all changes applied, skipped, and failed

## Post-Reconciliation

After all changes are applied:

1. The manifest used for reconciliation becomes the new "current state" manifest
2. The orchestration skill persists it via the `jfrog-system-config-repo` skill, respecting `state.destination`:
   - **`artifactory`**: Upload to the configured project/repo (Operation C)
   - **`git`**: Commit and push to the configured git repo (Operation F)
3. Report the upload/push location to the user
