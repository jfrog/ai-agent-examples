---
name: jfrog-provision-project
description: Provision a new project on the JFrog Platform via REST API. Use when the user wants to create a JFrog project, set up a new project in Artifactory, or as part of onboarding a GitHub repo to JFrog.
---

# JFrog Provision Project

Creates a project on the JFrog Platform. Projects are the top-level organizational unit that groups repositories, builds, and members.

## Inputs

- `project_key` -- 3-32 chars, lowercase letters and digits only, must start with a letter
- `display_name` -- human-readable name
- `description` -- optional project description

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

### 1. Validate project key

```bash
# Must be 3-32 lowercase alphanumeric, starting with a letter
echo "$PROJECT_KEY" | grep -qE '^[a-z][a-z0-9]{2,31}$' || echo "ERROR: Invalid project key"
```

### 2. Check if project already exists

```bash
STATUS=$(curl -s -o /dev/null -w '%{http_code}' \
  -H "Authorization: Bearer $JFROG_ACCESS_TOKEN" \
  "$JFROG_URL/access/api/v1/projects/$PROJECT_KEY")

if [ "$STATUS" = "200" ]; then
  echo "Project '$PROJECT_KEY' already exists. Skipping creation."
  # Proceed to next step in the onboarding chain
fi
```

### 3. Create the project

```bash
curl -sf -X POST "$JFROG_URL/access/api/v1/projects" \
  -H "Authorization: Bearer $JFROG_ACCESS_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "project_key": "'"$PROJECT_KEY"'",
    "display_name": "'"$DISPLAY_NAME"'",
    "description": "'"$DESCRIPTION"'",
    "admin_privileges": {
      "manage_members": true,
      "manage_resources": true,
      "index_resources": true
    }
  }'
```

Expected response: HTTP 201 with the created project JSON.

### 4. Verify creation

```bash
curl -sf -H "Authorization: Bearer $JFROG_ACCESS_TOKEN" \
  "$JFROG_URL/access/api/v1/projects/$PROJECT_KEY" | jq .
```

## Error Handling

- **409 Conflict**: Project already exists -- treat as success
- **400 Bad Request**: Invalid project key format -- report to user
- **403 Forbidden**: Token lacks permissions -- ask user to use a Platform Admin token

## Additional Resources

For full API spec details, see [reference.md](reference.md).
