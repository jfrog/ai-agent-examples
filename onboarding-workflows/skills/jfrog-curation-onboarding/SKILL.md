---
name: jfrog-curation-onboarding
description: Set up JFrog Curation with protection policies on an existing JFrog Platform instance. Checks if Curation is enabled, collects a notification email, then creates security, license, and operational risk policies on remote repositories. The "Block Malicious" policy blocks downloads; all others run in dry-run (audit) mode. Use when the user wants to set up curation, onboard curation, enable curation protection, or block malicious packages.
---

# JFrog Curation Onboarding

Sets up JFrog Curation protection on an existing JFrog Platform instance by verifying Curation is enabled and creating a set of security, license, and operational risk policies across remote repositories. Malicious packages are blocked; all other policy violations are logged in dry-run mode with email notifications.

## Trigger Phrases

Activate this skill when the user says things like:
- "Setup curation with my jfrog"
- "Onboard jfrog curation"
- "Connect my jfrog with curation"
- "Enable curation protection"
- "Block malicious packages"

## Operating Modes

This skill has two operating modes:

### Standalone Mode (Interactive)

Triggered directly by the user. Runs the full interactive workflow: prerequisite checks, repo discovery, email collection, scope selection, user confirmation, policy creation, and verification. This is the default mode described in the sections below.

### Automated Mode (Manifest-Driven)

Called by the `jfrog-project-onboarding` orchestrator when `curation.enabled` resolves to `true` for one or more projects. In this mode the skill:

- **Skips** prerequisite checks (Steps 0-1b) -- already verified by the orchestrator
- **Skips** interactive email collection (Step 4) -- uses `notification_email` from the manifest
- **Skips** interactive scope selection and user confirmation (Step 5) -- the orchestrator already collected confirmation
- **Executes** Steps 2 (check curation status), 3 (discover repos), 6 (enable curation on repos), 7 (create policies), 8 (verify), and 9 (report)

#### Automated Mode Inputs

| Input | Source | Description |
|-------|--------|-------------|
| `CURATED_REMOTE_REPOS` | Orchestrator | JSON array of remote repo keys from all curation-enabled projects (e.g., `["proj-npm-remote", "proj-pypi-remote"]`) |
| `CURATION_NOTIFY_EMAIL` | Manifest `jfrog.curation.notification_email` (or per-project override) | Email for policy violation notifications |

#### Automated Mode Scope Logic

- If **all** projects in the manifest have curation enabled (i.e., every remote repo on the platform created by this onboarding run is curated), use **`all_repos`** scope -- this also covers repos added in the future.
- If only **some** projects have curation enabled, use **`specific_repos`** scope with `CURATED_REMOTE_REPOS` to limit policies to the curated repos only.

#### Automated Mode Policy Creation

Policies are created **once** after all projects are processed (not per-project), because curation policies are platform-level resources with unique names. The orchestrator collects all curated remote repos across projects and invokes this skill a single time.

If policies already exist (409), they are treated as success -- no update is attempted. If the user later onboards additional projects with curation enabled, the existing policies continue to work if they use `all_repos` scope. For `specific_repos` scope, the orchestrator should update the existing policies to include the new repos (see "Updating Existing Policies" below).

#### Updating Existing Policies

When onboarding adds new curated repos to a platform that already has curation policies (from a previous onboarding run), the existing `specific_repos` policies need their `repo_include` list expanded. The automated mode handles this by:

1. Listing existing policies (`GET /xray/api/v1/curation/policies`)
2. For each of the 8 expected policies, check if it already exists
3. If it exists with `specific_repos` scope, **update** it (`PUT /xray/api/v1/curation/policies/{id}`) to merge the new repos into `repo_include`
4. If it exists with `all_repos` scope, no update is needed (new curated repos are automatically covered)
5. If it does not exist, create it as usual

```bash
# Example: update an existing specific_repos policy to include new repos
EXISTING_POLICY_ID="<id from GET response>"
EXISTING_REPOS=$(jq -r '.repo_include' /tmp/existing-policy.json)
NEW_REPOS='["proj2-npm-remote","proj2-pypi-remote"]'
MERGED_REPOS=$(echo "$EXISTING_REPOS" "$NEW_REPOS" | jq -s 'add | unique')

HTTP_CODE=$(curl -s -o /tmp/curation-update-resp.json -w "%{http_code}" \
  -X PUT "$JFROG_URL/xray/api/v1/curation/policies/$EXISTING_POLICY_ID" \
  -H "Authorization: Bearer $JFROG_ACCESS_TOKEN" \
  -H "Content-Type: application/json" \
  -d "$(jq -n --argjson repos "$MERGED_REPOS" \
    --arg email "$CURATION_NOTIFY_EMAIL" \
    '{repo_include: $repos, notify_emails: [$email]}')")

if [ "$HTTP_CODE" = "200" ]; then
  echo "OK: Policy updated with new repos"
else
  echo "ERROR: Failed to update policy (HTTP $HTTP_CODE)"
  cat /tmp/curation-update-resp.json
fi
```

## Prerequisites

Before starting, load credentials and verify access. If **any** check fails, **abort immediately**.

### Step 0: Load credentials

```bash
if [ -z "$JFROG_URL" ] || [ -z "$JFROG_ACCESS_TOKEN" ]; then
  if [ -f .env ]; then
    set -a; source .env; set +a
  fi
fi

[ -z "$JFROG_URL" ] && echo "FAIL: JFROG_URL is not set" && exit 1
[ -z "$JFROG_ACCESS_TOKEN" ] && echo "FAIL: JFROG_ACCESS_TOKEN is not set" && exit 1
echo "OK: JFROG_URL=$JFROG_URL"
echo "OK: JFROG_ACCESS_TOKEN is set"
```

### Step 1a: Validate token (run with `required_permissions: ["full_network"]`)

```bash
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" \
  -H "Authorization: Bearer $JFROG_ACCESS_TOKEN" \
  "$JFROG_URL/artifactory/api/system/version")

if [ "$HTTP_CODE" = "200" ]; then
  echo "OK: Token authentication successful"
else
  echo "FAIL: Token authentication failed (HTTP $HTTP_CODE)"
  exit 1
fi
```

### Step 1b: Validate platform admin privileges (run with `required_permissions: ["full_network"]`)

```bash
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" \
  -H "Authorization: Bearer $JFROG_ACCESS_TOKEN" \
  "$JFROG_URL/access/api/v1/config/security/authentication/basic_authentication_enabled")

if [ "$HTTP_CODE" = "200" ]; then
  echo "OK: Platform admin privileges confirmed"
else
  echo "ABORT: Token does not have platform admin privileges (HTTP $HTTP_CODE)"
  echo "Generate an admin token from: $JFROG_URL/ui/admin/configuration/security/access_tokens"
  exit 1
fi
```

## API Reference

| Operation | Method | Endpoint | Notes |
|-----------|--------|----------|-------|
| Check curation status | GET | `/artifactory/api/curation/status` | Returns `{"status": true/false, ...}` |
| List remote repos with curation status | GET | `/artifactory/api/curation/repositories` | Returns `curated` boolean and `project` per repo |
| Enable/disable curation on a repo | POST | `/artifactory/api/repositories/{repoKey}` | Send `{"curated": true}` (standard repo update) |
| Create curation policy | POST | `/xray/api/v1/curation/policies` | See payload fields in Step 7 |
| List curation policies | GET | `/xray/api/v1/curation/policies` | Returns `{data: [...], meta: {...}}` |
| Get policy by ID | GET | `/xray/api/v1/curation/policies/{id}` | |
| Update policy | PUT | `/xray/api/v1/curation/policies/{id}` | |
| Delete policy | DELETE | `/xray/api/v1/curation/policies/{id}` | |

## Policies to Create

The skill creates the following 8 curation policies. **Block Malicious** blocks downloads; all others use **dry-run** (audit) mode to log violations without blocking.

| # | Policy Name | Condition ID | Action | Risk Type |
|---|-------------|-------------|--------|-----------|
| 1 | Block Malicious | 1 | block | Security |
| 2 | CVE CVSS 9 and above with fix | 2 | dry_run | Security |
| 3 | License GNU AGPL | 9 | dry_run | Legal |
| 4 | License GNU GPL | 10 | dry_run | Legal |
| 5 | License GNU LGPL | 11 | dry_run | Legal |
| 6 | Aged no newer version | 12 | dry_run | Operational |
| 7 | Aged newer available | 13 | dry_run | Operational |
| 8 | Immature moderate | 15 | dry_run | Operational |

**Policy naming rule**: The JFrog API rejects policy names containing special characters (`+`, `:`, `(`, `)`, etc.). Use only alphanumeric characters, spaces, and hyphens in policy names.

## Workflow

### Step 2: Check Curation Status (run with `required_permissions: ["full_network"]`)

Verify that Curation is enabled on the platform. Uses the safe API call pattern.

```bash
HTTP_CODE=$(curl -s -o /tmp/curation-status.json -w "%{http_code}" \
  -H "Authorization: Bearer $JFROG_ACCESS_TOKEN" \
  "$JFROG_URL/artifactory/api/curation/status")

if [ "$HTTP_CODE" = "200" ]; then
  echo "OK: Curation API is reachable"
  cat /tmp/curation-status.json
else
  echo "ABORT: Curation is not enabled or not available (HTTP $HTTP_CODE)"
  echo ""
  echo "To enable Curation, go to:"
  echo "  $JFROG_URL/ui/admin/curation-settings/general"
  echo ""
  echo "Enable Curation in the settings, then run this skill again."
  exit 1
fi
```

**If the API returns a non-200 status**, abort and instruct the user:

> Curation is not enabled on your JFrog Platform.
>
> To enable it, navigate to **Curation Settings > General** in the JFrog UI:
> `{JFROG_URL}/ui/admin/curation-settings/general`
>
> Please enable the following settings:
> 1. **Enable Curation** -- activates curation on the platform
> 2. **Enable compliant version selection** (optional, but recommended) -- when a package version is blocked by a curation policy, Artifactory will automatically suggest the closest compliant version that passes all policies
>
> After enabling Curation, run this skill again.

### Step 3: Discover Remote Repositories and Curation Status (run with `required_permissions: ["full_network"]`)

Before creating policies, discover the remote repositories and their curation status. Use the curation-specific endpoint which returns the `curated` boolean and `project` for each repo.

```bash
HTTP_CODE=$(curl -s -o /tmp/curation-remote-repos.json -w "%{http_code}" \
  -H "Authorization: Bearer $JFROG_ACCESS_TOKEN" \
  "$JFROG_URL/artifactory/api/curation/repositories")

if [ "$HTTP_CODE" = "200" ]; then
  echo "OK: Retrieved remote repositories with curation status"
  jq -r '.[] | "\(.key) (pkg: \(.packageType), project: \(.project // "none"), curated: \(.curated))"' /tmp/curation-remote-repos.json
else
  echo "ERROR: Could not list remote repositories (HTTP $HTTP_CODE)"
  cat /tmp/curation-remote-repos.json
  exit 1
fi
```

**Response format** (each element):
```json
{
  "key": "myrepo-npm-remote",
  "packageType": "npm",
  "url": "https://registry.npmjs.org",
  "project": "myproj",
  "curated": false
}
```

Group the repositories by project for display. The `curated` field indicates whether curation is already enabled on each repo -- this is critical for the later enablement step.

### Step 4: Collect Notification Email

**Ask the user** for an email address to receive notifications when curation policies are violated.

> What email address should receive notifications for Curation policy violations?

Store the email as `CURATION_NOTIFY_EMAIL`. This email will be included in the `notify_emails` field of every policy created in Step 7.

### Step 5: Present Plan and Get Confirmation

Present the user with a clear plan **before** creating or applying any policies. The plan must include:

1. **Policies to create**: list all 8 policies with their actions (block vs dry_run)
2. **Notification email**: the email provided in Step 4
3. **Scope options**: Ask the user to choose one:
   - **Global (all remote repositories)** -- the policies apply to every remote repo on the platform, including repos added in the future
   - **Specific project(s)** -- the policies apply only to remote repos belonging to the selected JFrog project(s). List the discovered projects and their remote repo counts so the user can choose.

**Present the plan like this** (adapt based on discovered repos):

> **Curation Policies Plan**
>
> The following policies will be created:
>
> | # | Policy | Action | Description |
> |---|--------|--------|-------------|
> | 1 | Block Malicious | **Block** | Blocks all known malicious packages (JFrog Security Research) |
> | 2 | CVE CVSS 9 and above with fix | Dry Run | Audits packages with critical CVE scores where a fix exists |
> | 3 | License GNU AGPL | Dry Run | Audits packages with GNU AGPL license |
> | 4 | License GNU GPL | Dry Run | Audits packages with GNU GPL license |
> | 5 | License GNU LGPL | Dry Run | Audits packages with GNU LGPL license |
> | 6 | Aged no newer version | Dry Run | Audits aged package versions with no newer version identified |
> | 7 | Aged newer available | Dry Run | Audits aged package versions where a newer version exists |
> | 8 | Immature moderate | Dry Run | Audits immature package versions (< 14 days old) |
>
> **Notification email**: {CURATION_NOTIFY_EMAIL}
>
> **Discovered remote repositories**: {N} total
> - Global (no project): {list or count}
> - Project `{key1}`: {list or count}
> - Project `{key2}`: {list or count}
>
> **How would you like to apply these policies?**
> 1. **Globally** -- applies to all {N} remote repositories (and any future ones)
> 2. **Per project** -- applies only to remote repositories in specific project(s)

**Wait for the user to choose** the scope option. If they choose per-project, ask which project(s) to include.

After the user selects the scope, present a **final confirmation** before proceeding:

> **Please confirm the following changes:**
>
> - Create **8 curation policies** (1 blocking + 7 dry-run)
> - Notification email: **{CURATION_NOTIFY_EMAIL}**
> - Scope: {Global / Projects: key1, key2}
> - Affected repositories: {list of repo names}
>
> Proceed? (yes/no)

**Do not create or apply anything until the user explicitly confirms.**

### Step 6: Enable Curation on Target Repositories (run with `required_permissions: ["full_network"]`)

**IMPORTANT**: Curation policies can only target repos that have `curated: true`. If no repos are curated, even an `all_repos` policy will fail with *"policy cannot have empty effective scope"*. Repos are **not** curated by default.

Check whether the target repos have `curated: true` (from Step 3 data). For any repo with `curated: false`, enable curation via the standard Artifactory repo update API:

```bash
# Enable curation on a single repo
HTTP_CODE=$(curl -s -o /tmp/curation-enable-resp.json -w "%{http_code}" \
  -X POST "$JFROG_URL/artifactory/api/repositories/$REPO_KEY" \
  -H "Authorization: Bearer $JFROG_ACCESS_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"curated": true}')

if [ "$HTTP_CODE" = "200" ]; then
  echo "OK: Curation enabled on $REPO_KEY"
else
  echo "ERROR: Failed to enable curation on $REPO_KEY (HTTP $HTTP_CODE)"
  cat /tmp/curation-enable-resp.json
fi
```

Loop over all target repos that have `curated: false`, enabling each one with a `sleep 1` between calls to avoid rate limiting. After enabling, re-fetch `GET /artifactory/api/curation/repositories` and verify all target repos now show `curated: true`.

**For global scope**: enable curation on **all** remote repos that are currently `curated: false`.
**For specific_repos scope**: enable curation only on the selected repos.

### Step 7: Create Curation Policies (run with `required_permissions: ["full_network"]`)

After the user confirms and curation is enabled on target repos (Step 6), create all 8 curation policies with the chosen scope. Loop through each policy definition, creating them one at a time with a `sleep 1` between calls to avoid rate limiting.

#### Policy definitions

```bash
POLICIES='[
  {"name":"Block Malicious","condition_id":"1","policy_action":"block","waiver_request_config":"forbidden"},
  {"name":"CVE CVSS 9 and above with fix","condition_id":"2","policy_action":"dry_run","waiver_request_config":"forbidden"},
  {"name":"License GNU AGPL","condition_id":"9","policy_action":"dry_run","waiver_request_config":"forbidden"},
  {"name":"License GNU GPL","condition_id":"10","policy_action":"dry_run","waiver_request_config":"forbidden"},
  {"name":"License GNU LGPL","condition_id":"11","policy_action":"dry_run","waiver_request_config":"forbidden"},
  {"name":"Aged no newer version","condition_id":"12","policy_action":"dry_run","waiver_request_config":"forbidden"},
  {"name":"Aged newer available","condition_id":"13","policy_action":"dry_run","waiver_request_config":"forbidden"},
  {"name":"Immature moderate","condition_id":"15","policy_action":"dry_run","waiver_request_config":"forbidden"}
]'
```

#### Option A: Global scope

```bash
POLICY_COUNT=$(echo "$POLICIES" | jq length)
for i in $(seq 0 $(($POLICY_COUNT - 1))); do
  POLICY_NAME=$(echo "$POLICIES" | jq -r ".[$i].name")
  CONDITION_ID=$(echo "$POLICIES" | jq -r ".[$i].condition_id")
  POLICY_ACTION=$(echo "$POLICIES" | jq -r ".[$i].policy_action")
  WAIVER_CONFIG=$(echo "$POLICIES" | jq -r ".[$i].waiver_request_config")

  PAYLOAD=$(jq -n \
    --arg name "$POLICY_NAME" \
    --arg condition_id "$CONDITION_ID" \
    --arg policy_action "$POLICY_ACTION" \
    --arg waiver "$WAIVER_CONFIG" \
    --arg email "$CURATION_NOTIFY_EMAIL" \
    '{
      name: $name,
      condition_id: $condition_id,
      scope: "all_repos",
      policy_action: $policy_action,
      waiver_request_config: $waiver,
      notify_emails: [$email]
    }')

  HTTP_CODE=$(curl -s -o /tmp/curation-policy-resp.json -w "%{http_code}" \
    -X POST "$JFROG_URL/xray/api/v1/curation/policies" \
    -H "Authorization: Bearer $JFROG_ACCESS_TOKEN" \
    -H "Content-Type: application/json" \
    -d "$PAYLOAD")

  if [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "201" ]; then
    echo "OK: Policy '$POLICY_NAME' created successfully (global scope)"
  elif [ "$HTTP_CODE" = "409" ]; then
    echo "OK: Policy '$POLICY_NAME' already exists (no action needed)"
  else
    echo "ERROR: Failed to create policy '$POLICY_NAME' (HTTP $HTTP_CODE)"
    cat /tmp/curation-policy-resp.json
  fi

  sleep 1
done
```

#### Option B: Project-scoped

When the user selects specific projects, create the policies scoped to those projects' remote repositories. Build the repo list from the discovered repos in Step 3.

```bash
# SELECTED_REPOS should be a JSON array string, e.g. '["repo1","repo2"]'
POLICY_COUNT=$(echo "$POLICIES" | jq length)
for i in $(seq 0 $(($POLICY_COUNT - 1))); do
  POLICY_NAME=$(echo "$POLICIES" | jq -r ".[$i].name")
  CONDITION_ID=$(echo "$POLICIES" | jq -r ".[$i].condition_id")
  POLICY_ACTION=$(echo "$POLICIES" | jq -r ".[$i].policy_action")
  WAIVER_CONFIG=$(echo "$POLICIES" | jq -r ".[$i].waiver_request_config")

  PAYLOAD=$(jq -n \
    --arg name "$POLICY_NAME" \
    --arg condition_id "$CONDITION_ID" \
    --arg policy_action "$POLICY_ACTION" \
    --arg waiver "$WAIVER_CONFIG" \
    --arg email "$CURATION_NOTIFY_EMAIL" \
    --argjson repo_include "$SELECTED_REPOS" \
    '{
      name: $name,
      condition_id: $condition_id,
      scope: "specific_repos",
      repo_include: $repo_include,
      policy_action: $policy_action,
      waiver_request_config: $waiver,
      notify_emails: [$email]
    }')

  HTTP_CODE=$(curl -s -o /tmp/curation-policy-resp.json -w "%{http_code}" \
    -X POST "$JFROG_URL/xray/api/v1/curation/policies" \
    -H "Authorization: Bearer $JFROG_ACCESS_TOKEN" \
    -H "Content-Type: application/json" \
    -d "$PAYLOAD")

  if [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "201" ]; then
    echo "OK: Policy '$POLICY_NAME' created for selected project repos"
  elif [ "$HTTP_CODE" = "409" ]; then
    echo "OK: Policy '$POLICY_NAME' already exists (no action needed)"
  else
    echo "ERROR: Failed to create policy '$POLICY_NAME' (HTTP $HTTP_CODE)"
    cat /tmp/curation-policy-resp.json
  fi

  sleep 1
done
```

**Payload fields**:

| Field | Value | Description |
|-------|-------|-------------|
| `name` | Policy display name | See policy definitions table above |
| `condition_id` | `"1"`, `"2"`, `"9"`, etc. | Built-in condition ID matching the policy type |
| `scope` | `all_repos`, `specific_repos`, or `pkg_types` | Scope mode |
| `repo_include` | `["repo-key-1", ...]` | (Only for `specific_repos`) List of remote repo keys to protect |
| `repo_exclude` | `["repo-key-1", ...]` | (Optional, only for `all_repos`) List of remote repo keys to exclude |
| `pkg_types_include` | `["npm", "PyPI", ...]` | (Only for `pkg_types`) List of package types to protect |
| `policy_action` | `block` or `dry_run` | `block` for Block Malicious; `dry_run` for all others |
| `waiver_request_config` | `forbidden` | **Required for all policies** (block and dry_run). No waiver requests allowed |
| `notify_emails` | `["email@example.com"]` | Email addresses notified on policy violations |

**Scope modes**:
- `all_repos` -- applies to all curated remote repos. Optionally use `repo_exclude` to omit specific repos.
- `specific_repos` -- requires `repo_include` with at least one curated repo key. Cannot use `repo_exclude` or `pkg_types_include`.
- `pkg_types` -- requires `pkg_types_include` with at least one package type. Cannot use `repo_include` or `repo_exclude`.

### Step 8: Verify Policies (run with `required_permissions: ["full_network"]`)

Confirm all policies exist by listing all curation policies.

```bash
HTTP_CODE=$(curl -s -o /tmp/curation-policies-list.json -w "%{http_code}" \
  -H "Authorization: Bearer $JFROG_ACCESS_TOKEN" \
  "$JFROG_URL/xray/api/v1/curation/policies")

if [ "$HTTP_CODE" = "200" ]; then
  echo "Current curation policies:"
  jq -r '.data[] | "  - \(.name) (action: \(.policy_action), scope: \(.scope))"' /tmp/curation-policies-list.json
else
  echo "WARN: Could not list policies (HTTP $HTTP_CODE)"
fi
```

### Step 9: Report Results

After completing the workflow, report a summary to the user.

**For global scope:**

> **Curation Onboarding Complete**
>
> - Platform: `{JFROG_URL}`
> - Curation status: Enabled
> - Notification email: **{CURATION_NOTIFY_EMAIL}**
> - Scope: **Global** -- all remote repositories ({N} current + any future repos)
> - Policies created:
>
>   | Policy | Action |
>   |--------|--------|
>   | Block Malicious | **Block** |
>   | CVE CVSS 9 and above with fix | Dry Run |
>   | License GNU AGPL | Dry Run |
>   | License GNU GPL | Dry Run |
>   | License GNU LGPL | Dry Run |
>   | Aged no newer version | Dry Run |
>   | Aged newer available | Dry Run |
>   | Immature moderate | Dry Run |
>
> All remote repositories are now protected. Malicious packages are blocked; all other policies run in audit mode (dry-run) and will generate email notifications without blocking downloads.
>
> View all policies: `{JFROG_URL}/ui/package-curation/policies`

**For project scope:**

> **Curation Onboarding Complete**
>
> - Platform: `{JFROG_URL}`
> - Curation status: Enabled
> - Notification email: **{CURATION_NOTIFY_EMAIL}**
> - Scope: **Project-scoped** -- {project key(s)}
> - Protected repositories: {list of repo names}
> - Policies created:
>
>   | Policy | Action |
>   |--------|--------|
>   | Block Malicious | **Block** |
>   | CVE CVSS 9 and above with fix | Dry Run |
>   | License GNU AGPL | Dry Run |
>   | License GNU GPL | Dry Run |
>   | License GNU LGPL | Dry Run |
>   | Aged no newer version | Dry Run |
>   | Aged newer available | Dry Run |
>   | Immature moderate | Dry Run |
>
> The selected project repositories are now protected. Malicious packages are blocked; all other policies run in audit mode (dry-run) and will generate email notifications without blocking downloads.
> **Note**: Remote repositories outside the selected project(s) are **not** covered by these policies. Re-run this skill to extend coverage to additional projects or switch to global scope.
>
> View all policies: `{JFROG_URL}/ui/package-curation/policies`

## Error Handling

| HTTP Code | Meaning | Action |
|-----------|---------|--------|
| 200/201 | Success | Proceed |
| 400 "empty effective scope" | No repos have `curated: true` | Enable curation on target repos first (Step 6), then retry |
| 400 "repository X is not curated" | A specific repo in `repo_include` has `curated: false` | Enable curation on that repo via `POST /artifactory/api/repositories/{key}` with `{"curated": true}` |
| 409 | Policy already exists | Treat as success, report to user |
| 401/403 | Auth failure or insufficient privileges | Abort with guidance |
| Non-200 on curation status | Curation not enabled | Abort, instruct user to enable from UI |

## Related skills

For Curation API concepts, policy types, and manual policy management, see **platform-features** (`jfrog-curation`).
