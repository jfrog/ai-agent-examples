---
name: jfrog-create-users-groups
description: Create users and groups on the JFrog Platform via REST API. Use when onboarding discovers missing users or groups, or when the user wants to create JFrog platform users/groups. Supports assigning users to groups during creation and setting a default password.
---

# JFrog Create Users & Groups

Prefer **`jf api`** ([../../../platform-features/skills/jfrog-cli/jf-api-patterns.md](../../../platform-features/skills/jfrog-cli/jf-api-patterns.md)); **`curl`** in checks below is **fallback**.

Creates users and groups on the JFrog Platform. Typically invoked during onboarding when the manifest references users or groups that do not yet exist, but can also be used standalone.

## Inputs

- `users` -- list of users to create:
  ```yaml
  users:
    - { name: alice, email: alice@example.com, groups: [backend-team] }
    - { name: bob, email: bob@example.com }
  ```
- `groups` -- list of groups to create:
  ```yaml
  groups:
    - { name: backend-team, description: "Backend developers" }
    - { name: devops, description: "DevOps team" }
  ```
- `default_password` -- password to set for newly created users (from manifest `jfrog.default_password` or prompted interactively)

## Load Credentials

```bash
# Load .env if JFROG_URL or JFROG_ACCESS_TOKEN are not already set
if [ -z "$JFROG_URL" ] || [ -z "$JFROG_ACCESS_TOKEN" ]; then
  if [ -f .env ]; then
    set -a; source .env; set +a
  fi
fi
```

## Workflow

### 1. Determine Default Password

The default password is required for creating new users. Resolve it in this order:

1. **Manifest field**: Read `jfrog.default_password` from the manifest YAML
2. **Interactive prompt**: If not in the manifest, ask the user to provide a default password

Password requirements: at least 8 characters, must include uppercase, lowercase, and a digit. Validate before proceeding.

### 2. Create Groups First

Groups must be created **before** users so that users can be assigned to groups during creation.

#### Check if group exists

```bash
jf api "/access/api/v2/groups/$GROUP_NAME" >/tmp/jf-cug-group.json 2>/tmp/jf-cug-group.code
HTTP_CODE=$(tr -d '\r\n' < /tmp/jf-cug-group.code)
```

- `200` = already exists, skip creation
- `404` = does not exist, proceed to create

#### Create a group (run with `required_permissions: ["full_network"]`)

```bash
jf api /access/api/v2/groups -X POST \
  -H "Content-Type: application/json" \
  -d '{
    "name": "'"$GROUP_NAME"'",
    "description": "'"$GROUP_DESCRIPTION"'",
    "auto_join": false
  }'
```

Expected response: HTTP 201 with the created group JSON.

### 3. Create Users

After all groups are created, create users. Users can optionally be assigned to groups during creation.

#### Check if user exists

```bash
jf api "/access/api/v2/users/$JFROG_USER_NAME" >/tmp/jf-cug-user.json 2>/tmp/jf-cug-user.code
HTTP_CODE=$(tr -d '\r\n' < /tmp/jf-cug-user.code)
```

- `200` = already exists, skip creation
- `404` = does not exist, proceed to create

#### Create a user (run with `required_permissions: ["full_network"]`)

```bash
jf api /access/api/v2/users -X POST \
  -H "Content-Type: application/json" \
  -d '{
    "username": "'"$JFROG_USER_NAME"'",
    "password": "'"$DEFAULT_PASSWORD"'",
    "email": "'"$EMAIL"'",
    "admin": false,
    "profile_updatable": true,
    "disable_ui_access": false,
    "internal_password_disabled": false,
    "groups": ['"$GROUPS_JSON_ARRAY"']
  }'
```

Expected response: HTTP 201 with the created user JSON.

#### Expire password (force change on first login)

Immediately after successfully creating a user, expire their password so they are forced to set a new one on first login to Artifactory. Run with `required_permissions: ["full_network"]`:

```bash
jf api /access/api/v2/users/$JFROG_USER_NAME/password/expire -X POST \
  -H "Content-Type: application/json"
```

Expected response: HTTP 200. If this call fails, log a warning but **do not** fail the overall user creation -- the user was already created successfully.

**Field details:**

| Field | Required | Description |
|-------|----------|-------------|
| `username` | Yes | Unique username |
| `password` | Yes | Initial password (recommend forcing change on first login) |
| `email` | Yes | User email address. If not provided in manifest, derive as `{username}@{domain}` where domain comes from `JFROG_URL` |
| `admin` | No | Whether the user is a platform admin (default: `false`) |
| `profile_updatable` | No | Whether the user can update their profile (default: `true`) |
| `disable_ui_access` | No | Block UI login (default: `false`) |
| `internal_password_disabled` | No | Disable internal password, e.g., for SSO-only (default: `false`) |
| `groups` | No | List of group names to assign the user to on creation. Defaults to `["readers"]` if not specified |

### 4. Verify Creation

After creating all users and groups, verify they exist:

```bash
# Verify user
jf api "/access/api/v2/users/$JFROG_USER_NAME" | jq '{username, email, status}'

# Verify group
jf api "/access/api/v2/groups/$GROUP_NAME" | jq '{name, description}'
```

## Integration with Onboarding Workflow

When called from the onboarding orchestration (via `jfrog-manage-members`), the flow is:

1. **Validate** all users and groups referenced in the manifest
2. **Collect missing** users and groups into two lists
3. **Prompt the user**: Display the missing users/groups and ask whether to create them
   - If the user confirms, invoke this skill to create them
   - If the user declines, **abort** onboarding (same as the original behavior)
4. **Re-validate**: After creation, confirm all users/groups now exist before proceeding to role assignment

### Prompt Format

When missing users/groups are found, present them clearly:

```
The following users/groups referenced in the manifest do not exist in the JFrog Platform:

Missing users:
  - alice
  - bob

Missing groups:
  - backend-team

Would you like to create them now? (Yes / No)
```

Use the `AskQuestion` tool with Yes/No options. If Yes, proceed with creation. If No, abort.

### User Details Collection

For each missing user, if the manifest does not include `email`, ask the user to provide emails -- or offer to auto-generate them using the pattern `{username}@{jfrog-domain}`.

For group assignments during user creation:

- **Manifest mode**: Check the manifest for any `groups` field on the user entry. If no groups are specified for a user, assign them to the `readers` group by default.
- **Interactive mode**: For each user, ask which group(s) they should belong to (one question at a time per the `interaction-questions` rule). If the user does not specify a group, default to the `readers` group.

The `readers` group is a built-in JFrog group and does not need to be created. However, if any other default or user-specified group does not exist, it must be created in Step 2 before user creation. Every user must belong to at least one group.

If the user entry includes groups that are also being created, those groups are created first (Step 2 above).

## Batch Processing

**CRITICAL -- Shell Variable Naming**: When iterating over users in loops or functions, **never** use `USERNAME` as a variable name (not even as a `local` variable). On macOS and Linux, `$USERNAME` is a reserved environment variable that resolves to the current OS user. Use `$JFROG_USER_NAME` or another prefixed name like `$UNAME` instead. See the `jfrog-platform` rule for the full list.

When processing multiple users/groups from the manifest:

1. **Create all groups first** -- iterate and create each, collecting successes and failures
2. **Create all users** -- iterate and create each (with group assignments), and immediately expire each new user's password to force a change on first login. Collect successes and failures.
3. **Report results** -- display a summary of what was created and what failed

```
Creation Summary:
  Groups created: backend-team, devops
  Groups skipped (already existed): platform-team
  Users created: alice, bob
  Users failed: charlie (HTTP 400: invalid email)
```

## Error Handling

- **201 Created**: Success
- **409 Conflict**: User/group already exists -- treat as success, skip creation
- **400 Bad Request**: Invalid input (e.g., bad email, weak password) -- report the error and continue with remaining items
- **403 Forbidden**: Token lacks permission -- abort and report
- **415 Unsupported Media Type**: Missing `Content-Type: application/json` header -- fix and retry

## Security Notes

- The default password is a **temporary** password. The skill automatically expires it after creation, forcing users to set a new password on first login to Artifactory.
- Never log or echo passwords in command output. Use `-s` (silent) flag on curl.
- The `default_password` in the manifest is sensitive -- remind users not to commit it to git. The `.env` file pattern is preferred for secrets.
