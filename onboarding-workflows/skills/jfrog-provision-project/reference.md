# JFrog Projects REST API Reference

## Create Project

**Endpoint**: `POST /access/api/v1/projects`

**Headers**:
```
Authorization: Bearer <access-token>
Content-Type: application/json
```

**Request Body**:
```json
{
  "project_key": "myproj",
  "display_name": "My Project",
  "description": "Optional description",
  "admin_privileges": {
    "manage_members": true,
    "manage_resources": true,
    "manage_security_assets": true,
    "index_resources": true,
    "allow_ignore_rules": false
  },
  "storage_quota_bytes": -1,
  "soft_limit": false,
  "storage_quota_email_notification": true
}
```

**Response**: `201 Created`
```json
{
  "project_key": "myproj",
  "display_name": "My Project",
  "description": "Optional description",
  "admin_privileges": { ... },
  "storage_quota_bytes": -1
}
```

## Get Project

**Endpoint**: `GET /access/api/v1/projects/{project_key}`

**Response**: `200 OK` with project JSON, or `404 Not Found`.

## List Projects

**Endpoint**: `GET /access/api/v1/projects`

**Response**: `200 OK` with array of project objects.

## Update Project

**Endpoint**: `PUT /access/api/v1/projects/{project_key}`

Same body format as create. Returns `200 OK`.

## Delete Project

**Endpoint**: `DELETE /access/api/v1/projects/{project_key}`

**Response**: `204 No Content`.

## Project Key Rules

- 3 to 32 characters
- Lowercase letters (a-z) and digits (0-9) only
- Must start with a lowercase letter
- Cannot be changed after creation
