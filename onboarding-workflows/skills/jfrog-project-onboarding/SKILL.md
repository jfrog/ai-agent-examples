---
name: jfrog-project-onboarding
description: Orchestrate end-to-end JFrog Platform onboarding for GitHub projects. Provisions JFrog projects, creates Artifactory repositories, adds members, configures OIDC, configures package managers, and updates CI workflows. Use when the user wants to onboard, connect, or integrate GitHub repos with JFrog, or when processing an onboarding manifest.
---

# JFrog Project Onboarding (Master Orchestration)

This is the entry-point skill for onboarding GitHub projects to the JFrog Platform.

## Prerequisites Check

Before starting, load credentials and verify **all** prerequisites. If **any** check fails, **abort immediately** -- do not proceed with any onboarding steps. Report which check(s) failed and guide the user to fix them.

### Step 1: Load credentials (run in normal sandbox)

```bash
# Load .env if JFROG_URL or JFROG_ACCESS_TOKEN are not already set
if [ -z "$JFROG_URL" ] || [ -z "$JFROG_ACCESS_TOKEN" ]; then
  if [ -f .env ]; then
    set -a; source .env; set +a
  fi
fi

# Verify vars are set
[ -z "$JFROG_URL" ] && echo "FAIL: JFROG_URL is not set" && exit 1
[ -z "$JFROG_ACCESS_TOKEN" ] && echo "FAIL: JFROG_ACCESS_TOKEN is not set" && exit 1
echo "OK: JFROG_URL=$JFROG_URL"
echo "OK: JFROG_ACCESS_TOKEN is set"
```

### Step 2a: Validate token authentication (run with `required_permissions: ["full_network"]`)

Verify the token is valid by calling an authenticated endpoint:

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

### Step 2b: Validate platform admin privileges (MANDATORY -- run with `required_permissions: ["full_network"]`)

Verify the token has **platform admin** privileges by calling an admin-only endpoint. **If this check fails, abort immediately -- do not proceed with any onboarding steps.**

```bash
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" \
  -H "Authorization: Bearer $JFROG_ACCESS_TOKEN" \
  "$JFROG_URL/access/api/v1/config/security/authentication/basic_authentication_enabled")

if [ "$HTTP_CODE" = "200" ]; then
  echo "OK: Platform admin privileges confirmed"
else
  echo "ABORT: Token does not have platform admin privileges (HTTP $HTTP_CODE)"
  echo "A platform admin token is REQUIRED for onboarding."
  echo "Generate an admin token from: $JFROG_URL/ui/admin/configuration/security/access_tokens"
  exit 1
fi
```

**CRITICAL**: A non-admin token is a hard stop. Do not attempt to create projects, repositories, OIDC configurations, or any other resources. Report the failure and wait for the user to provide an admin token.

### Step 2c: Check subscription type and OIDC preference (run with `required_permissions: ["full_network"]`)

Read the `github.oidc_setup` flag from the manifest to determine the user's preferred authentication method for CI workflows. Then check whether the JFrog subscription supports OIDC:

```bash
# Read OIDC preference from manifest (defaults to false if not set)
OIDC_SETUP=$(yq '.github.oidc_setup // false' "$MANIFEST_FILE")

SUBSCRIPTION_TYPE=$(curl -s -H "Authorization: Bearer $JFROG_ACCESS_TOKEN" \
  "$JFROG_URL/artifactory/api/system/license" | jq -r '.subscriptionType')

echo "Subscription type: $SUBSCRIPTION_TYPE"
echo "OIDC setup requested: $OIDC_SETUP"

if [[ "$SUBSCRIPTION_TYPE" == enterprise_xray* ]] || [[ "$SUBSCRIPTION_TYPE" == enterprise_plus* ]]; then
  echo "OK: OIDC is available (subscription: $SUBSCRIPTION_TYPE)"
  OIDC_AVAILABLE=true
else
  OIDC_AVAILABLE=false
  if [ "$OIDC_SETUP" = "true" ]; then
    echo "ABORT: OIDC was requested (github.oidc_setup: true) but the JFrog subscription"
    echo "       ($SUBSCRIPTION_TYPE) does not support OIDC."
    echo ""
    echo "To fix this, either:"
    echo "  1. Upgrade to an Enterprise X or Enterprise+ subscription, OR"
    echo "  2. Set 'github.oidc_setup: false' in the manifest to use secrets-based auth."
    exit 1
  else
    echo "INFO: OIDC is NOT available (subscription: $SUBSCRIPTION_TYPE). Will use secrets-based auth for CI."
  fi
fi
```

**Decision matrix:**

| `github.oidc_setup` | Subscription supports OIDC | Result |
|----------------------|---------------------------|--------|
| `true` | Yes | Proceed with OIDC setup |
| `true` | No | **ABORT** -- user wants OIDC but platform cannot provide it |
| `false` | Yes or No | Skip OIDC, use secrets-based auth |

Store both `OIDC_SETUP` and `OIDC_AVAILABLE` for later use by the OIDC skill and CI workflow skill.

### Step 3: Tools check

```bash
jq --version && echo "OK: jq installed" || echo "FAIL: jq not found"
yq --version && echo "OK: yq installed" || echo "FAIL: yq not found"
```

### Abort Policy

**CRITICAL**: If any prerequisite check fails, you **must**:
1. Stop all onboarding work immediately
2. Report clearly which check(s) failed and why
3. Guide the user on how to fix the issue
4. Wait for the user to confirm the fix
5. Re-run **all** prerequisite checks from scratch before proceeding

**Non-admin token = hard abort**: If the token does not have platform admin privileges (Step 2b), this is an absolute blocker. Do not attempt any operations whatsoever -- no project creation, no repo creation, no OIDC, nothing. The user must provide an admin token before anything can proceed.

Do **not** attempt partial onboarding. All checks must pass before any onboarding step begins.

### Step 0: State Persistence Check

After all prerequisite checks pass, invoke the **`jfrog-system-config-repo`** skill to check for prior manifests. The behavior depends on `state.destination` in the manifest (or defaults to `artifactory` if no manifest is available yet).

#### When `state.destination` = `artifactory` (default)

Run with `required_permissions: ["full_network"]`.

Read configurable project/repo from the manifest (or use defaults `system` / `system-configuration`):

1. **Ensure project + repo**: Call Operation A from `jfrog-system-config-repo`. Creates the state project and generic repository if they do not already exist. The project is platform-admin-only.
2. **Check for existing manifests**: Call Operation B to list manifest snapshots.

#### When `state.destination` = `git`

Run with `required_permissions: ["all"]`.

1. **Verify git repo accessible**: Call Operation D from `jfrog-system-config-repo`.
2. **Check for existing manifests**: Call Operation E to clone the repo and list timestamp folders.

#### Common: User choice when manifests are found

3. **If manifests are found** (either backend):
   - Alert the user: "Found N existing configuration manifest(s). The latest is from `<timestamp>`."
   - Ask (using `AskQuestion` with three options):
     - **Retrieve latest and update** -- download the latest manifest, save it locally, display it to the user. Proceed to **Option C (Reconcile)** where the user can edit the manifest and reconcile changes.
     - **Retrieve latest and re-onboard** -- download the latest manifest and use it as the input for **Option A (Manifest-Driven)**.
     - **Start fresh** -- ignore existing manifests and proceed normally (user provides a manifest via Option A, or enters details interactively via Option B).

4. **If no manifests are found**: proceed normally to the Workflow section (no alert).

**Note**: If no manifest is available at this point (interactive mode, first run), default to `artifactory` with `system` / `system-configuration`. The interactive session will collect the state destination preference in Phase 1.

### Step 0b: Detect Existing Naming Patterns

After prerequisites and state persistence checks pass, and before creating any projects or repositories, invoke the **`detect-existing-patterns`** skill to check whether the platform already has projects and repos with an established naming convention.

**When to run**: This step runs once per onboarding session, not per project. It applies to both Option A (manifest-driven) and Option B (interactive).

- **Option A (manifest-driven)**: Run detection after the manifest is parsed but before the skill chain begins. Use the first project's `project_key` and `ecosystems` from the manifest to generate example names.
- **Option B (interactive)**: Run detection after Phase 2 collects the first project's key (Q3) and ecosystems (Q5), so the examples use real values.

**Inputs to the skill**:
- `JFROG_URL`, `JFROG_ACCESS_TOKEN` -- already loaded
- `new_project_key` -- the first project key from the manifest or interactive input
- `new_ecosystems` -- the first project's ecosystems
- `state_project_key` -- the state project key (from `state.artifactory.project`, default `system`) so it is excluded from analysis

**Behavior**:
- If the platform has no existing projects/repos (or only the state project), the skill silently returns the **standard** naming pattern. No question is asked.
- If existing repos are found and their pattern **matches** the standard pattern, the skill reports this and returns the standard pattern. No question is asked.
- If existing repos are found and their pattern **differs** from the standard, the skill presents both options (detected vs. standard) with concrete examples and asks the user to choose using `AskQuestion`.

**Output**: A `naming_pattern` object (see `detect-existing-patterns` skill for the schema). Store this and pass it to `jfrog-create-repos` in Step 2 for every project in the onboarding run.

## Workflow

### Option A: Manifest-Driven (Batch)

If the user explicitly provides a manifest file path, use it directly. Otherwise, if a manifest file is found locally (e.g., in the repository root or `templates/` directory), **do not assume it should be used**.

#### URL Mismatch Check (MANDATORY before offering a found manifest)

Before asking the user whether to use a locally found manifest, compare the manifest's `jfrog.url` against the active `$JFROG_URL` (from environment or `.env`):

```bash
MANIFEST_URL=$(yq -r '.jfrog.url // ""' "$FOUND_MANIFEST")
# Compare against $JFROG_URL (already loaded from env/.env)
```

- **If URLs match**: ask the user whether to use the manifest or enter details manually.
- **If URLs differ**: the manifest belongs to a different JFrog instance. **Do not offer it** to the user for the current session. Instead, inform the user and fall through to **Option B** (interactive mode), which will generate a new manifest for the active instance:
  > Found `<path>` but it targets `<manifest-url>`, while the active JFrog instance is `<active-url>`. This manifest belongs to a different instance and will not be modified. Proceeding with interactive input for the active instance.

This prevents accidentally appending projects to a manifest that targets a different JFrog Platform instance.

If the manifest URL matches, ask the user first:

> I found a manifest file at `<path>`. Would you like to use it for onboarding, or would you prefer to enter project details manually?

Only proceed with the manifest after the user explicitly confirms. If the user declines, fall through to **Option B** (interactive mode).

Once a manifest is confirmed:
1. Read and parse the manifest file
2. Extract all projects, repos, and members
3. Run **Manifest Validation** (see below) -- abort if any check fails
4. Run **Step 0b: Detect Existing Naming Patterns** using the first project's key and ecosystems. Store the returned `naming_pattern`.
5. For each project entry, execute the skill chain below (passing `naming_pattern` to Step 2)
6. Track progress using todos -- one set of todos per project

### Option B: Interactive (No Manifest)

When the user does not provide a manifest YAML, collect inputs interactively by asking questions **one at a time** (per the `interaction-questions` rule). Gather all data before any provisioning begins.

#### Phase 1 -- Global Settings

Ask these questions first. All are optional -- if the user skips or accepts defaults, the indicated defaults are used.

| # | Question | Required | Default | Format |
|---|----------|----------|---------|--------|
| 0a | Where should the configuration state be stored? | No | Artifactory | `Artifactory` or `Git` (use `AskQuestion` tool). Determines where the manifest is persisted for audit trail. |
| 0b | (if git) Which git repo? | **Yes** (if git) | (required) | `owner/repo` format (e.g., `myorg/jfrog-config`). Uses the GitHub host from Q1. |
| 0c | (if git) Path in the repo? | No | `/` (root) | Directory path for manifest storage (e.g., `manifests/`). |
| 0d | (if artifactory) Custom project/repo names? | No | `system` / `system-configuration` | Ask if the user wants to override the default project and repo names. If yes, collect both values. |
| 1 | What is your GitHub host? | No | `github.com` | Hostname string (e.g., `github.com` or `github.mycompany.com`). The user can type a value or accept the default. |
| 2 | Would you like to use OIDC (secretless) authentication for CI workflows? | No | No | Yes / No (use the `AskQuestion` tool with two options). Explain that OIDC requires an Enterprise X or Enterprise+ JFrog subscription. If the user selects Yes but the subscription does not support it, the existing abort logic in Step 2c applies. |
| 2a | Enable Xray indexing on repositories? | No | Yes | Yes / No. When enabled, local and remote repos are added to Xray's indexed resources. |
| 2b | Enable Curation on remote repositories? | No | No | Yes / No. When enabled, Curation is activated on remote repos to vet open-source packages AND the standard curation policies (Block Malicious, CVE, License, Operational Risk) are created. Requires a compatible JFrog subscription. |
| 2c | (if curation = yes) Notification email for curation policy violations? | **Yes** (if curation enabled) | (none -- must be provided) | Email address. Receives notifications when curation policies are violated. Stored as `jfrog.curation.notification_email`. |

#### Phase 2 -- Project Loop

Repeat for each project. **At least one project is required.** After collecting the first project, ask whether the user wants to add another. If yes, loop back to question 3.

| # | Question | Required | Default | Format |
|---|----------|----------|---------|--------|
| 3 | What is the project key? | **Yes** | none | 2-32 lowercase alphanumeric characters, must start with a letter. This is the only strictly required input. |
| 4 | What is the display name for this project? | No | Title-cased project key (e.g., key `webapp` becomes `Webapp`) | Free text. |
| 5 | Which ecosystems does this project use? | No | If GitHub repos are provided later, offer to auto-detect; otherwise empty | Multi-select from: npm, maven, pip, go, docker, helm. Use the `AskQuestion` tool with `allow_multiple: true`. |
| 5a | Override Xray/Curation settings for this project? | No | No (inherit global) | Yes / No. If Yes, ask follow-up: enable Xray? (Yes/No) and enable Curation? (Yes/No). If Curation is enabled for this project, also ask for a project-specific notification email (optional -- inherits global `notification_email` from Q2c if omitted). If No, inherit global defaults from Q2a/Q2b. |
| 5b | Any custom repository definitions for this project? | No | none | Yes / No. If Yes, collect repos one at a time: key, type (local/remote/virtual), package_type, and type-specific fields (url for remote; aggregated_repos and default_deployment_repo for virtual). Loop until the user is done. Custom repos are merged with ecosystem-generated repos per the smart merge logic. |
| 6 | Which GitHub repositories should be associated with this project? | No | none | Comma-separated `owner/repo` entries (e.g., `myorg/my-app, myorg/my-lib`). If the user skips this, the package-manager config, CI workflow, and OIDC steps are skipped for this project. |
| 7 | Any users to add to this project? | No | none | Comma-separated `username:role` pairs. Valid roles: `Project Admin`, `Developer`, `Contributor`, `Viewer`. Example: `alice:Developer, bob:Contributor`. |
| 8 | Any groups to add to this project? | No | none | Comma-separated `groupname:role` pairs. Example: `backend-team:Developer, devops:Project Admin`. |
| 9 | Would you like to add another project? | -- | No | Yes / No (use the `AskQuestion` tool). If Yes, loop back to question 3. |

#### Naming Pattern Detection (after first project's Q3 + Q5)

After collecting the first project's key (Q3) and ecosystems (Q5), run **Step 0b: Detect Existing Naming Patterns** before continuing to Q5a. Pass the first project's key and ecosystems as `new_project_key` and `new_ecosystems` so the skill can generate concrete examples. Store the returned `naming_pattern` for use by all projects in this session.

This only runs once (after the first project). Subsequent projects added via Q9 reuse the same `naming_pattern`.

#### Ecosystem Auto-Detection

If the user provides GitHub repos (Q6) but skips ecosystems (Q5), offer to auto-detect ecosystems by inspecting the repos. Look for these marker files:

| File | Ecosystem |
|------|-----------|
| `package.json` | npm |
| `pom.xml` or `build.gradle` | maven |
| `requirements.txt`, `setup.py`, or `pyproject.toml` | pip |
| `go.mod` | go |
| `Dockerfile` | docker |
| `Chart.yaml` | helm |

If auto-detection finds ecosystems, confirm them with the user before proceeding.

#### Assembled Data Structure

After all questions are answered, assemble the collected inputs into a YAML manifest (same structure as `templates/manifest-template.yaml`):

```yaml
jfrog:
  url: <from JFROG_URL env var>
  xray:
    enabled: <from Q2a, default true>
  curation:
    enabled: <from Q2b, default false>
    notification_email: <from Q2c, required if curation enabled>

github:
  host: <from Q1, default "github.com">
  oidc_setup: <from Q2, default false>
  branch_name: jfrog-onboarding  # always use this default

state:
  destination: <from Q0a, default "artifactory">
  artifactory:                     # only if destination = artifactory
    project: <from Q0d, default "system">
    repository: <from Q0d, default "system-configuration">
  git:                             # only if destination = git
    repo: <from Q0b>
    path: <from Q0c, default "/">
    branch: main                   # default

jfrog_projects:
  - project_key: <from Q3>
    display_name: <from Q4>
    xray:                          # only if Q5a override was chosen
      enabled: <from Q5a follow-up>
    curation:                      # only if Q5a override was chosen
      enabled: <from Q5a follow-up>
      notification_email: <from Q5a follow-up, optional -- inherits global>
    ecosystems: [<from Q5>]
    repositories: [<from Q5b>]     # only if custom repos were defined
    github_repos: [<from Q6>]
    members:
      users: [<from Q7, parsed into {name, role} objects>]
      groups: [<from Q8, parsed into {name, role} objects>]
  # ... additional projects if the user added more via Q9
```

#### Write Manifest to File

After assembling the data structure, **write it to a YAML file** before proceeding:

1. Write the manifest to `./jfrog-manifest.yaml` (or another path if the user specifies).
2. Display the generated manifest to the user for review.
3. Ask the user to confirm before proceeding with execution.

This ensures every onboarding run (whether manifest-driven or interactive) has a reproducible manifest artifact.

This assembled structure then feeds into the **same** prerequisite checks (Step 2c for OIDC gating) and **Manifest Validation** steps (Steps 5-6 below) as Option A. After validation passes, the same skill chain executes.

#### Handling Skipped Optionals

| What was skipped | Effect on skill chain |
|------------------|----------------------|
| No GitHub repos for a project | Skip Steps 4-6 (OIDC, package-manager config, CI workflows) for that project |
| No members for a project | Skip Step 3 (member assignment) for that project |
| No ecosystems and no repositories and no GitHub repos | Only execute Step 1 (provision JFrog project) |
| No ecosystems and no repositories but GitHub repos given | Attempt auto-detection; if nothing detected, ask user to specify at least one ecosystem or skip repo-related steps |
| No ecosystems but repositories given | Create only the custom repos listed (no auto-generated trios) |
| Both ecosystems and repositories given | Smart merge: generate ecosystem trios, then apply custom overrides/additions |

#### Summary Before Execution

Before running any prerequisite checks, display a summary of all collected inputs to the user and ask for confirmation. Example:

```
State destination: artifactory (system / system-configuration)
GitHub host: github.com
OIDC: No
Xray (global): enabled
Curation (global): disabled
Curation notification email: (N/A -- curation disabled)

Project 1:
  Key: webapp
  Display name: Web Application
  Ecosystems: npm, docker
  Custom repositories: 1 (webapp-npm-release: local/npm)
  Xray: enabled (inherited)
  Curation: disabled (inherited)
  GitHub repos: myorg/my-web-app
  Users: alice (Developer)
  Groups: frontend-team (Contributor)

Proceed with onboarding? (Yes / No)
```

If the user says No, allow them to correct any values before proceeding.

## Manifest Validation

After parsing the manifest (or receiving interactive input), and **before creating anything on JFrog or GitHub**, you **must** validate all referenced external resources. If **any** validation fails, **abort immediately** -- do not create any JFrog projects, repositories, or other resources.

### Step 5: Validate GitHub Repositories Exist (run with `required_permissions: ["all"]`)

For **every** repository listed under `github_repos` across all projects in the manifest, verify the repository exists:

```bash
GITHUB_HOST="https://github.com"  # or from manifest github.host
REPO="owner/repo"                  # from manifest github_repos[]

git ls-remote "${GITHUB_HOST}/${REPO}.git" HEAD 2>/dev/null
# If this fails (non-zero exit), the repo does not exist or is not accessible
```

**CRITICAL**:
- Check **all** repos first and collect **all** failures
- If **any** repo is missing or inaccessible, **abort** and list every failing repo
- **Do not create any JFrog resources** until all GitHub repos are confirmed to exist
- The user must fix the manifest or create the missing repos before retrying

### Step 6: Validate Users and Groups -- Create if Missing (run with `required_permissions: ["full_network"]`)

For **every** user and group listed under `members` across **all** projects, verify they exist in the JFrog Platform:

```bash
# Check user exists
HTTP_CODE=$(curl -s -o /dev/null -w '%{http_code}' \
  -H "Authorization: Bearer $JFROG_ACCESS_TOKEN" \
  "$JFROG_URL/access/api/v2/users/$JFROG_USER_NAME")
# 200 = exists, 404 = does not exist

# Check group exists
HTTP_CODE=$(curl -s -o /dev/null -w '%{http_code}' \
  -H "Authorization: Bearer $JFROG_ACCESS_TOKEN" \
  "$JFROG_URL/access/api/v2/groups/$GROUPNAME")
# 200 = exists, 404 = does not exist
```

**Check all users and groups first** and collect all missing items. Then:

1. If **all** users and groups exist -- proceed to the next step
2. If **any** are missing -- offer to create them:
   - Display a clear list of all missing users and groups
   - Ask: "Would you like to create these users/groups now?" (Yes / No)
   - **If Yes**: invoke the **`jfrog-create-users-groups`** skill
     - Read `jfrog.default_password` from the manifest for the initial password (prompt if not set)
     - Use `email` and `groups` fields from user entries in the manifest if available
     - Create groups **first**, then users (so group membership assignments work)
     - After creation, **re-validate** all users/groups to confirm they now exist
   - **If No**: **abort** onboarding and list every missing user/group so the user can create them manually
3. **Do not create any JFrog projects or repositories** until all users and groups are confirmed to exist

### Validation Abort Policy

If **any** manifest validation check fails:
1. **Do not proceed** with any onboarding step (no project creation, no repo creation, nothing)
2. Report **all** failures at once so the user can fix everything in a single pass
3. Wait for the user to confirm the fixes
4. Re-run **all** validations (prerequisites + manifest validations) from scratch

## Skill Chain

Execute these skills in order for each project. Use the skill name as a reference to trigger the appropriate sub-skill:

### Step 1: Provision JFrog Project
**Skill**: `jfrog-provision-project`
- Creates the JFrog project if it does not already exist
- Input: `project_key`, `display_name`

### Step 2: Create Artifactory Repositories
**Skill**: `jfrog-create-repos`
- Creates repos from ecosystems (auto-generated trios), custom `repositories` list, or both (smart merge)
- Input: `project_key`, `ecosystems`, `repositories`, `xray_enabled`, `curation_enabled`, `naming_pattern`
- `naming_pattern` comes from Step 0b (detect-existing-patterns). If not provided, the skill uses the standard pattern.
- Uses templates from `templates/repos/` for ecosystem-generated repos; builds inline JSON for custom repos
- Skip this step if neither `ecosystems` nor `repositories` is set for the project
- **Xray/Curation resolution**: For each project, resolve the effective Xray and Curation settings:
  1. If the project has `xray.enabled` set, use that value
  2. Otherwise, fall back to global `jfrog.xray.enabled`
  3. If neither is set, default to `true` for Xray
  4. Same logic for Curation (default `false`)
- The resolved `xray_enabled` controls the `{{XRAY_INDEX}}` placeholder in repo templates and whether Xray indexing API calls are made
- The resolved `curation_enabled` controls whether Curation is enabled on remote repos after creation

### Step 3: Add Members
**Skill**: `jfrog-manage-members` (which may invoke `jfrog-create-users-groups`)
- Adds users and groups to the JFrog project
- Input: `project_key`, `members`, `default_password` (from `jfrog.default_password`)
- Skip if no members specified
- Users and groups were validated in Step 6 -- if any were missing, they were either created (user confirmed) or onboarding was aborted
- The `jfrog-manage-members` skill handles the full flow: validate existence, offer to create missing via `jfrog-create-users-groups`, then assign roles

### Step 4: OIDC Setup
**Skill**: `jfrog-oidc-setup`
- Configures OIDC provider and identity mappings for secretless CI authentication
- Input: `project_key`, `github_repos`, `github_host`, `OIDC_SETUP`, `OIDC_AVAILABLE`
- **If `OIDC_SETUP` is false**: skip this step entirely and log that secrets-based auth will be used (regardless of subscription)
- **If `OIDC_SETUP` is true AND `OIDC_AVAILABLE` is true**: configure provider and create identity mappings for each repo in `github_repos`
- **If `OIDC_SETUP` is true AND `OIDC_AVAILABLE` is false**: this case should never be reached (the prerequisite check in Step 2c aborts first)
- Output: `oidc_provider_name` (passed to CI workflow skill; empty string when OIDC is skipped)

### Step 5: Configure Package Managers
**Skill**: `github-configure-package-managers`
- Updates package manager config files in the GitHub repos
- Input: `github_repos`, `project_key`, `ecosystems`, JFrog URL
- Processes **each repo** in `github_repos`: clones, creates branch, adds config files, pushes
- Instructs user to open PRs for each repo

### Step 6: Configure CI Workflows
**Skill**: `github-configure-ci-workflows`
- Modifies GitHub Actions workflows for Artifactory integration
- Input: `github_repos`, `project_key`, `ecosystems`, `oidc_provider_name` (from Step 4, or empty)
- If `oidc_provider_name` is set (i.e., `github.oidc_setup: true` and OIDC was configured): uses OIDC authentication in workflows
- If `oidc_provider_name` is empty (i.e., `github.oidc_setup: false`): uses `JF_ACCESS_TOKEN` secret-based authentication
- Processes **each repo** in `github_repos`: clones, creates branch, modifies workflows, pushes
- Instructs user to open PRs for each repo (or appends to the package-manager branch)

### Post-Project Steps (Platform-Level)

These steps run **once** after all per-project steps are complete, not per-project.

### Step 7: Curation Policies
**Skill**: `jfrog-curation-onboarding` (automated mode)

Curation policies are **platform-level** resources (not project-scoped), so they are created once after all projects are processed.

**Skip this step entirely if no project has curation enabled** (i.e., all projects resolved `curation_enabled` to `false`).

When at least one project has curation enabled:

1. **Resolve notification email**: For each curation-enabled project, resolve the notification email:
   - If the project has `curation.notification_email` set, use it
   - Otherwise, fall back to global `jfrog.curation.notification_email`
   - If neither is set, **prompt the user** for an email address before proceeding
   - If multiple projects have different notification emails, use the **global** email for the policies (curation policies support only one email list per policy). Log a note that per-project email overrides are not applied at the policy level.

2. **Collect curated remote repos**: Gather the list of all remote repo keys from projects where `curation_enabled` resolved to `true`. These repos already have `curated: true` set (from Step 2's `jfrog-create-repos` skill).

3. **Determine scope**:
   - If **all** projects in the manifest have curation enabled, use **`all_repos`** scope (covers future repos too)
   - If only **some** projects have curation enabled, use **`specific_repos`** scope with the collected repo keys

4. **Invoke `jfrog-curation-onboarding`** in automated mode with:
   - `CURATED_REMOTE_REPOS` -- the JSON array of remote repo keys
   - `CURATION_NOTIFY_EMAIL` -- the resolved notification email
   - The skill checks curation platform status, ensures `curated: true` on all target repos (belt-and-suspenders), creates or updates the 8 standard policies, verifies them, and reports results.

5. **Handle pre-existing policies**: If this is not the first onboarding run and policies already exist:
   - `all_repos` policies require no update (new curated repos are automatically covered)
   - `specific_repos` policies are updated to merge new repos into `repo_include` (see automated mode in the curation skill)

**Input**: notification email (from manifest), curated remote repo keys (from Step 2 across all projects)
**Output**: 8 curation policies created or updated

### Option C: Reconcile (Update Mode)

When the user wants to update or reconcile JFrog configuration based on manifest changes (e.g., triggered from Step 0 when the user chooses "Retrieve latest and update", or when the user explicitly says "update JFrog from manifest" or "reconcile manifest changes"):

**Important**: The reconcile process uses exactly two manifest sources:
- **Desired manifest**: must be **explicitly provided by the user** (a file path they specify). Do **not** auto-discover or use locally found manifest files. If the user does not provide a manifest path, ask them for one.
- **Baseline**: must come from the **configured state backend** (Artifactory or git) -- the last successfully applied manifest. Never use locally found files as a baseline.

1. **Obtain the desired manifest** -- the user must explicitly provide the manifest file path. If the user chose "Retrieve latest and update" in Step 0, the downloaded manifest from the state backend becomes the starting point -- save it locally, let the user edit it, and the user then provides the edited file path as the desired manifest.
2. The user edits the manifest to reflect the desired state.
3. **Obtain the baseline from the state backend** -- the reconcile skill needs a baseline (last-applied manifest) for a 3-way comparison. The baseline is always retrieved from the configured state backend (Artifactory or git). If Step 0 already downloaded a manifest from the state backend, pass it as the `baseline` input to avoid re-downloading. Otherwise, the reconcile skill's Phase 0 will retrieve it from the state backend.
   - If the user chose "Retrieve latest and update" in Step 0, the originally downloaded manifest (before edits) serves as the baseline for comparison.
   - If the user provides a new manifest directly, the reconcile skill retrieves the baseline from the state backend in Phase 0.
4. Invoke the **`jfrog-reconcile-manifest`** skill with `manifest` (desired state, explicitly provided by user) and optionally `baseline` (from state backend), which:
   - Retrieves the baseline from the state backend if one was not already provided (Phase 0)
   - Reads current JFrog state for all projects in the manifest (Phase 1)
   - Computes a 3-way diff when baseline is available, or 2-way diff otherwise (Phase 2)
   - Presents the diff to the user for approval, showing manifest changes, drift, and planned actions (Phase 3)
   - Applies only the delta operations (Phase 4)
5. After reconciliation completes, upload the final manifest (see Post-Completion below).

## Post-Completion: Persist Manifest

After **all** onboarding steps complete successfully (regardless of which Option was used -- A, B, or C):

1. The final manifest YAML is always available:
   - **Option A**: the input manifest file
   - **Option B**: the generated manifest file written during interactive collection
   - **Option C**: the reconciled manifest (with any user edits applied)

2. Read `state.destination` from the manifest (default: `artifactory`).

3. **If `artifactory`**: Invoke Operation C from `jfrog-system-config-repo` to upload the manifest.
   - Report: "Configuration manifest saved to Artifactory at `<repo>/<timestamp>/jfrog-configuration-manifest.yaml`."

4. **If `git`**: Invoke Operation F from `jfrog-system-config-repo` to commit and push the manifest.
   - Report: "Configuration manifest pushed to `<repo>@<branch>:<path>/<timestamp>/jfrog-configuration-manifest.yaml`."

This creates an audit trail of every onboarding run and enables future reconciliation.

## Progress Tracking

For batch onboarding, create a todo per project, plus a platform-level todo for curation policies:
```
- [ ] Onboard {project_key}: provision -> repos -> members -> OIDC -> pkg-mgr -> CI
- [ ] (repeat for each project)
- [ ] Curation policies (if any project has curation enabled)
```

Mark each sub-step as complete as you go. Report a summary when all projects are done.

## Error Handling

- If a project already exists (409), proceed to the next step
- If a repository already exists (409), skip creation and continue
- If git push fails, report the error and continue with the next project
- If manifest upload fails (post-completion), warn the user but do not fail the overall onboarding
- Always provide a final summary of successes and failures
