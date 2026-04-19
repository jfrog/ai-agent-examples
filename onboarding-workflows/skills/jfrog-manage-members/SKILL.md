---
name: jfrog-manage-members
description: Add users and groups to a JFrog Platform project with role assignments. Use when the user wants to manage project membership, add developers to a JFrog project, or assign roles to teams.
---

# JFrog Manage Members

Prefer **`jf api`** ([../../../platform-features/skills/jfrog-cli/jf-api-patterns.md](../../../platform-features/skills/jfrog-cli/jf-api-patterns.md)); **`curl`** below is **fallback**.

Adds users and groups to a JFrog project with appropriate role assignments.

## Inputs

- `project_key` -- the JFrog project key
- `members` -- object with optional `users` and `groups` arrays:
  ```yaml
  members:
    users:
      - { name: john, role: Developer }
    groups:
      - { name: backend-team, role: Contributor }
  ```

## Load Credentials

```bash
# Load .env if JFROG_URL or JFROG_ACCESS_TOKEN are not already set
if [ -z "$JFROG_URL" ] || [ -z "$JFROG_ACCESS_TOKEN" ]; then
  if [ -f .env ]; then
    set -a; source .env; set +a
  fi
fi
```

## Available Roles

| Role | Permissions |
|------|-------------|
| Project Admin | Full project management |
| Developer | Deploy, read, manage builds |
| Contributor | Deploy and read artifacts |
| Viewer | Read-only access |

Custom roles defined in the project are also supported -- use the exact role name.

## Add a User to a Project

```bash
jf api "/access/api/v1/projects/$PROJECT_KEY/users/$JFROG_USER_NAME" -X PUT \
  -H "Content-Type: application/json" \
  -d '{
    "name": "'"$JFROG_USER_NAME"'",
    "roles": ["Developer"]
  }'
```

## Add a Group to a Project

```bash
jf api "/access/api/v1/projects/$PROJECT_KEY/groups/$GROUPNAME" -X PUT \
  -H "Content-Type: application/json" \
  -d '{
    "name": "'"$GROUPNAME"'",
    "roles": ["Contributor"]
  }'
```

## List Current Members

```bash
# Users
jf api "/access/api/v1/projects/$PROJECT_KEY/users" | jq .

# Groups
jf api "/access/api/v1/projects/$PROJECT_KEY/groups" | jq .
```

## Pre-Assignment Validation (MANDATORY)

Before assigning **any** user or group to a project, you **must** verify they exist in the JFrog Platform. This validation must run against **all** users and groups in the list before making any assignment calls.

### Check user exists (run with `required_permissions: ["full_network"]`)

```bash
jf api "/access/api/v2/users/$JFROG_USER_NAME" >/tmp/jf-mm-user.json 2>/tmp/jf-mm-user.code
HTTP_CODE=$(tr -d '\r\n' < /tmp/jf-mm-user.code)

if [ "$HTTP_CODE" = "200" ]; then
  echo "OK: User '$JFROG_USER_NAME' exists"
else
  echo "MISSING: User '$JFROG_USER_NAME' does not exist (HTTP $HTTP_CODE)"
fi
```

### Check group exists (run with `required_permissions: ["full_network"]`)

```bash
jf api "/access/api/v2/groups/$GROUPNAME" >/tmp/jf-mm-group.json 2>/tmp/jf-mm-group.code
HTTP_CODE=$(tr -d '\r\n' < /tmp/jf-mm-group.code)

if [ "$HTTP_CODE" = "200" ]; then
  echo "OK: Group '$GROUPNAME' exists"
else
  echo "MISSING: Group '$GROUPNAME' does not exist (HTTP $HTTP_CODE)"
fi
```

### Handling Missing Users/Groups -- Offer to Create

**CRITICAL**: Check **all** users and groups first and collect **all** failures. If **any** user or group does not exist:

1. **Do not assign any members yet** -- not even the ones that passed validation
2. Report **all** missing users/groups in a clear list
3. **Offer to create them** using the `jfrog-create-users-groups` skill:
   - Present the missing users and groups to the user
   - Ask: "Would you like to create these users/groups now?" (Yes / No)
   - **If Yes**: invoke the `jfrog-create-users-groups` skill to create them
     - Use `jfrog.default_password` from the manifest (or prompt for a password if not set)
     - Use `email` and `groups` fields from the manifest user entries if available
     - Create groups **first**, then users (so group assignments work)
     - After creation, **re-validate** all users/groups to confirm they now exist
   - **If No**: **abort** the entire onboarding -- do not proceed with later steps
4. Only after all users/groups are confirmed to exist, proceed with role assignment

## Batch Processing

**CRITICAL -- Shell Variable Naming**: When iterating over users in loops or functions, **never** use `USERNAME` as a variable name (not even as a `local` variable). On macOS and Linux, `$USERNAME` is a reserved environment variable that resolves to the current OS user. Use `$JFROG_USER_NAME` or another prefixed name like `$UNAME` instead.

When processing a members list from the manifest:

1. **Validate all** users and groups exist (see above) -- abort if any are missing
2. Iterate over `members.users` -- call PUT for each user
3. Iterate over `members.groups` -- call PUT for each group
4. Report successes and failures at the end

## Error Handling

- **409 Conflict**: Member already exists with that role -- treat as success
- **404 Not Found**: User/group does not exist in the platform -- this should have been caught by pre-assignment validation; if it still occurs, **abort** and report to user
- **400 Bad Request**: Invalid role name -- report available roles
