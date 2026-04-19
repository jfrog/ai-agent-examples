---
name: jfrog-delete-project
description: Delete a JFrog project and all its repositories. Use when the user wants to remove, delete, or clean up a JFrog project, or mentions deleting JFrog resources.
---

# Delete JFrog Project

Prefer **`jf api`** ([../../../platform-features/skills/jfrog-cli/jf-api-patterns.md](../../../platform-features/skills/jfrog-cli/jf-api-patterns.md)); **`curl`** is **fallback** where shown.

This skill safely deletes a JFrog project and handles its associated repositories. Repos that are shared with other projects are **unassigned** (preserved) instead of deleted. It includes multiple confirmation steps and cross-project checks to prevent accidental data loss.

## Trigger Phrases

Activate this skill when the user says things like:
- "Delete JFrog project"
- "Remove JFrog project"
- "Clean up JFrog project"
- "Delete project from JFrog"

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

## Deletion Workflow

### Step 1: Load Credentials

Load credentials from `.env` (or environment variables):

```bash
# Load .env if vars are not already set
if [ -z "$JFROG_URL" ] || [ -z "$JFROG_ACCESS_TOKEN" ]; then
  if [ -f .env ]; then
    set -a; source .env; set +a
  fi
fi

# Verify vars are set
if [ -z "$JFROG_URL" ] || [ -z "$JFROG_ACCESS_TOKEN" ]; then
  echo "ERROR: JFROG_URL and JFROG_ACCESS_TOKEN must be set (in environment or .env file)"
  exit 1
fi

echo "Found credentials for: ${JFROG_URL}"
```

If credentials are missing, prompt the user:

> I need to connect to your JFrog Platform. Please provide:
> 1. **JFrog Platform URL** (e.g., `https://mycompany.jfrog.io`)
> 2. **Access Token** (with admin privileges)

**Validate the token:**

1. **Check authentication** is valid:
   ```bash
   jf api /artifactory/api/system/version
   ```

2. **Check platform admin privileges**:
   ```bash
   jf api /access/api/v1/config/security/authentication/basic_authentication_enabled >/tmp/jf-del-admin.json 2>/tmp/jf-del-admin.code
   HTTP_CODE=$(tr -d '\r\n' < /tmp/jf-del-admin.code)
   ```

   If HTTP code is 401 or 403:
   > The provided token does not have **platform admin** privileges.
   > This skill requires a platform admin token to delete projects and repositories.
   > Please provide a token with platform admin access.

### Step 2: Confirm Non-Production Environment

**IMPORTANT: This skill does NOT support deleting projects in production environments.**

After obtaining credentials, ask the user to confirm this is NOT a production JFrog instance:

> **Environment Check**
>
> You are connected to: `{jfrog-url}`
>
> **Is this a production JFrog environment?**
>
> Please confirm by answering: **Yes** (it IS production) or **No** (it is NOT production)

**Wait for the user's response.**

**If the user answers "Yes" (it IS production):**

> Deletion Refused
>
> I cannot delete projects from a production JFrog environment.
>
> This safety restriction is in place to prevent accidental deletion of production artifacts.
>
> If you need to delete a production project, please do so manually through the JFrog UI or contact your JFrog administrator.

**Do not proceed. End the workflow here.**

**If the user answers "No" (it is NOT production):**

> Confirmed: This is a non-production environment. Proceeding with deletion workflow.

**Only proceed if the user explicitly confirms this is NOT production.**

**If the user's response is unclear or ambiguous:**

> I need a clear answer. Is `{jfrog-url}` a **production** environment?
>
> Please answer **Yes** (production) or **No** (not production).

### Step 3: Get Project Name

If the user didn't specify a project, ask for it:

> Which JFrog project do you want to delete?
>
> You can provide either the **project key** (e.g., `myproject`) or the **display name** (e.g., `My Project`).

**Wait for the user to provide the project identifier.**

### Step 4: Resolve and Verify Project

The user's input may be a project key or a display name. Check both to find the project.

**First, try as a project key** (direct lookup):

```bash
USER_INPUT="user-provided-value"

jf api "/access/api/v1/projects/${USER_INPUT}" >/tmp/jf-del-proj.json 2>/tmp/jf-del-proj.code
HTTP_CODE=$(tr -d '\r\n' < /tmp/jf-del-proj.code)
```

**If found (HTTP 200)**, use it as the project key:

```bash
PROJECT_KEY="${USER_INPUT}"
PROJECT_DETAILS=$(cat /tmp/jf-del-proj.json)
DISPLAY_NAME=$(echo "${PROJECT_DETAILS}" | jq -r '.display_name')
echo "Found project: ${DISPLAY_NAME} (key: ${PROJECT_KEY})"
```

**If NOT found (HTTP 404)**, search by display name across all projects:

```bash
# List all projects and search by display name (case-insensitive)
MATCH=$(jf api /access/api/v1/projects | \
  jq -r --arg name "${USER_INPUT}" \
  '.[] | select(.display_name | ascii_downcase == ($name | ascii_downcase)) | .project_key')

if [ -n "$MATCH" ]; then
  PROJECT_KEY="$MATCH"
  echo "Found project by display name: key is '${PROJECT_KEY}'"
else
  echo "No project found matching '${USER_INPUT}' (checked both key and display name)"
fi
```

**If no match is found by either key or name**, inform the user and end:

> No project matching `{user-input}` was found in JFrog Platform at `{jfrog-url}`.
>
> I checked both project key and display name. No action taken.

**Do not proceed further if the project doesn't exist.**

### Step 5: List Repositories in Project

If the project exists, list all repositories that will be deleted.

**IMPORTANT**: The list repositories API (`GET /artifactory/api/repositories`) does **not** include `projectKey` in its response objects -- do NOT filter client-side with `jq` on `.projectKey`. Use the `?project=` query parameter to filter server-side ([docs](https://jfrog.com/help/r/jfrog-rest-apis/get-repositories-by-type-and-project)). If the API returns no results, fall back to the naming convention (`{project_key}-*`) to catch repos that may not have been properly assigned to the project.

```bash
# Get all repositories in the project using the project query parameter
jf api "/artifactory/api/repositories?project=${PROJECT_KEY}" >/tmp/jf-del-repos.json 2>/dev/null
REPOS=$(jq -r ".[].key" /tmp/jf-del-repos.json)

echo "Repositories in project ${PROJECT_KEY}:"
echo "${REPOS}"
```

If no repos are returned by the query parameter approach, fall back to **naming convention** as a secondary check:

```bash
if [ -z "$REPOS" ]; then
  jf api /artifactory/api/repositories >/tmp/jf-del-repos-all.json 2>/dev/null
  REPOS=$(jq -r --arg prefix "${PROJECT_KEY}-" '.[] | select(.key | startswith($prefix)) | .key' /tmp/jf-del-repos-all.json)

  if [ -n "$REPOS" ]; then
    echo "Found repos by naming convention (${PROJECT_KEY}-*):"
    echo "${REPOS}"
  fi
fi
```

### Step 6: Check Repos for Cross-Project Usage

Before deleting any repository, check whether it is also referenced by other JFrog projects. Repos that are shared with or used by other projects must be **unassigned** instead of deleted to avoid breaking those projects.

**List all projects and collect their repos** (with `sleep 1` between calls for rate-limit protection):

```bash
ALL_PROJECTS=$(jf api /access/api/v1/projects | jq -r '.[].project_key')

OTHER_REPOS=""
for OTHER_KEY in ${ALL_PROJECTS}; do
  if [ "$OTHER_KEY" = "$PROJECT_KEY" ]; then continue; fi
  jf api "/artifactory/api/repositories?project=${OTHER_KEY}" >/tmp/jf-del-other-repos.json 2>/dev/null
  PROJ_REPOS=$(jq -r '.[].key' /tmp/jf-del-other-repos.json)
  OTHER_REPOS="${OTHER_REPOS} ${PROJ_REPOS}"
  sleep 1
done
```

**Categorize repos** into two lists -- repos safe to delete vs. repos that must be unassigned:

```bash
REPOS_TO_DELETE=""
REPOS_TO_UNASSIGN=""
for REPO in ${REPOS}; do
  if echo "${OTHER_REPOS}" | grep -qw "$REPO"; then
    REPOS_TO_UNASSIGN="${REPOS_TO_UNASSIGN} ${REPO}"
  else
    REPOS_TO_DELETE="${REPOS_TO_DELETE} ${REPO}"
  fi
done
```

If any repos will be unassigned, identify **which** other projects reference them (for the confirmation prompt):

```bash
for REPO in ${REPOS_TO_UNASSIGN}; do
  SHARED_WITH=""
  for OTHER_KEY in ${ALL_PROJECTS}; do
    if [ "$OTHER_KEY" = "$PROJECT_KEY" ]; then continue; fi
    if echo "${OTHER_REPOS}" | grep -qw "$REPO"; then
      SHARED_WITH="${SHARED_WITH} ${OTHER_KEY}"
    fi
  done
  echo "${REPO} -> also in:${SHARED_WITH}"
done
```

### Step 7: Require Explicit Confirmation

**This is a destructive operation.** Display a warning and require explicit "Yes" confirmation. The prompt must show repos in two separate categories so the user understands which repos will be permanently deleted and which will only be unassigned (preserved for other projects).

> **WARNING: This action cannot be undone!**
>
> You are about to delete the JFrog project `{project-key}`.
>
> **Repositories to be DELETED** (only used by this project -- artifacts will be permanently removed):
> - `{project-key}-npm-local`
> - `{project-key}-npm-remote`
> - `{project-key}-npm`
> - *(list all repos from `REPOS_TO_DELETE`)*
>
> **Repositories to be UNASSIGNED** (also used by other projects -- will NOT be deleted):
> - `{project-key}-docker-remote` (also in: `otherproj`)
> - *(list all repos from `REPOS_TO_UNASSIGN` with the projects that share them)*
>
> To confirm, please type exactly: **Yes**

If there are no repos to unassign, omit the "UNASSIGNED" section entirely. If there are no repos to delete, omit the "DELETED" section and note that all repos will be preserved.

**Wait for the user's response.**

**Only proceed if the user responds with exactly "Yes"** (case-sensitive).

If the user responds with anything else (e.g., "yes", "y", "ok", "sure"):

> Deletion cancelled. You must type exactly "Yes" to confirm.

### Step 8: Unassign Shared Repos and Delete Non-Shared Repos

Handle repos in two phases. Unassign shared repos first, then delete non-shared repos.

**Phase 1 -- Unassign** repos that are used by other projects. This removes the repo from the project being deleted while preserving it (and its artifacts) for the other projects. Uses the [Unassign a Project from a Repository](https://docs.jfrog.com/projects/docs/project-management-tasks) API:

```bash
for REPO in ${REPOS_TO_UNASSIGN}; do
  echo "Unassigning repository: ${REPO} (shared with other projects)"

  jf api "/access/api/v1/projects/_/attach/repositories/${REPO}" -X DELETE >/dev/null 2>/tmp/jf-del-unassign.code
  HTTP_CODE=$(tr -d '\r\n' < /tmp/jf-del-unassign.code)

  if [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "204" ]; then
    echo "Unassigned: ${REPO}"
  else
    echo "Failed to unassign ${REPO}: HTTP ${HTTP_CODE}"
  fi
  sleep 1
done
```

**Phase 2 -- Delete** repos that are only used by this project:

```bash
for REPO in ${REPOS_TO_DELETE}; do
  echo "Deleting repository: ${REPO}"

  jf api "/artifactory/api/repositories/${REPO}" -X DELETE >/dev/null 2>/tmp/jf-del-repo.code
  HTTP_CODE=$(tr -d '\r\n' < /tmp/jf-del-repo.code)

  if [ "$HTTP_CODE" = "200" ]; then
    echo "Deleted: ${REPO}"
  else
    echo "Failed to delete ${REPO}: HTTP ${HTTP_CODE}"
  fi
  sleep 1
done
```

### Step 9: Delete the Project

After all repositories have been unassigned or deleted, delete the project:

```bash
# Delete the project
jf api "/access/api/v1/projects/${PROJECT_KEY}" -X DELETE >/dev/null 2>/tmp/jf-del-projdel.code
HTTP_CODE=$(tr -d '\r\n' < /tmp/jf-del-projdel.code)

if [ "$HTTP_CODE" = "204" ] || [ "$HTTP_CODE" = "200" ]; then
  echo "Project '${PROJECT_KEY}' deleted successfully"
else
  echo "Failed to delete project: HTTP ${HTTP_CODE}"
fi
```

### Step 10: Summary

Provide a summary of what was done:

> **Deletion Complete**
>
> **Project deleted**: `{project-key}`
>
> **Repositories deleted** (artifacts permanently removed):
> - `{project-key}-npm-local`
> - `{project-key}-npm-remote`
> - `{project-key}-npm`
> - *(list all repos from `REPOS_TO_DELETE`)*
>
> **Repositories unassigned** (preserved for other projects):
> - `{project-key}-docker-remote` (still in: `otherproj`)
> - *(list all repos from `REPOS_TO_UNASSIGN` with the projects that still use them)*
>
> **Note**: If you had local configuration files (`.npmrc`, `.env`) pointing to deleted repositories, you may want to clean them up. Unassigned repositories are still accessible via their other projects.

If there are no repos in either category, omit that section from the summary.

## API Reference

### Check Project Exists

```bash
jf api "/access/api/v1/projects/${PROJECT_KEY}"
```

- `200` = Project exists
- `404` = Project not found

### List Repositories by Project

Use the `project` query parameter to filter repos server-side ([docs](https://jfrog.com/help/r/jfrog-rest-apis/get-repositories-by-type-and-project)). The list API response does **not** include `projectKey` in its objects, so client-side filtering on that field will always return zero results.

```bash
jf api "/artifactory/api/repositories?project=${PROJECT_KEY}" | jq -r ".[].key"
```

### Unassign Repository from Project

Removes the project assignment from a repository without deleting it. The repo and its artifacts are preserved. See [Unassign a Project from a Repository](https://docs.jfrog.com/projects/docs/project-management-tasks).

```bash
jf api "/access/api/v1/projects/_/attach/repositories/${REPO_KEY}" -X DELETE
```

- `200` / `204` = Repository unassigned successfully
- `404` = Repository not found or not assigned to any project

### Delete Repository

```bash
jf api "/artifactory/api/repositories/${REPO_KEY}" -X DELETE
```

- `200` = Repository deleted
- `404` = Repository not found

### Delete Project

```bash
jf api "/access/api/v1/projects/${PROJECT_KEY}" -X DELETE
```

- `204` = Project deleted
- `404` = Project not found

## Safety Features

1. **Production environment block** - Refuses to delete projects in production environments
2. **Non-production confirmation** - Requires explicit confirmation that this is NOT production
3. **Project existence check** - Verifies project exists before attempting deletion
4. **Repository listing** - Shows user exactly what will be deleted vs. unassigned
5. **Cross-project sharing check** - Detects repos used by other projects and unassigns them instead of deleting
6. **Explicit confirmation** - Requires exact "Yes" response (case-sensitive)
7. **Two-phase repo handling** - Unassigns shared repos first, then deletes non-shared repos, then deletes the project
8. **Status reporting** - Reports success/failure for each unassign and deletion

## Error Handling

| Error | Cause | Action |
|-------|-------|--------|
| Project not found | Invalid project key | Inform user, end workflow |
| 401 Unauthorized | Invalid token | Ask user to check credentials |
| 403 Forbidden | Token lacks delete permissions | Ask user to use admin token |
| Repository deletion failed | Repository in use or protected | Report error, continue with others |
| Repository unassign failed | Repo not assigned or API error | Report error, continue with others |
| Project list API failed | Token issue or connectivity | Abort cross-project check, ask user to retry |
