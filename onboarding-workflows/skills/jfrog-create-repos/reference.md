# Artifactory Repository REST API Reference

## Create/Replace Repository

**Endpoint**: `PUT /artifactory/api/repositories/{repo-key}`

**Query Parameter**: `?project={project_key}` -- scopes the repo to a JFrog project

**Headers**:
```
Authorization: Bearer <access-token>
Content-Type: application/json
```

## Repository Types

### Local Repository
Stores internally-produced artifacts.

### Remote Repository
Proxies and caches artifacts from an upstream source.

### Virtual Repository
Aggregates local and remote repos under a single URL. Resolves from remote, deploys to default local.

## Upstream URLs by Ecosystem

| Ecosystem | Package Type | Remote URL |
|-----------|-------------|------------|
| npm | `npm` | `https://registry.npmjs.org` |
| Maven | `maven` | `https://repo1.maven.org/maven2` |
| PyPI | `pypi` | `https://files.pythonhosted.org` |
| Go | `go` | `https://proxy.golang.org` |
| Docker | `docker` | `https://registry-1.docker.io` |
| Helm | `helm` | `https://charts.helm.sh/stable` |

## Key JSON Fields

### All Repository Types

| Field | Type | Description |
|-------|------|-------------|
| `key` | string | Repository key (unique identifier) |
| `rclass` | string | `local`, `remote`, or `virtual` |
| `packageType` | string | `npm`, `maven`, `pypi`, `go`, `docker`, `helm` |
| `projectKey` | string | JFrog project key to scope this repo |
| `description` | string | Optional description |

### Remote-Specific

| Field | Type | Description |
|-------|------|-------------|
| `url` | string | Upstream URL to proxy |
| `externalDependenciesEnabled` | boolean | Allow external dependencies (Docker) |

### Virtual-Specific

| Field | Type | Description |
|-------|------|-------------|
| `repositories` | string[] | List of aggregated repo keys |
| `defaultDeploymentRepo` | string | Local repo for deployments |
| `externalDependenciesEnabled` | boolean | Allow external dependencies |

## Resolution URLs (for clients)

| Ecosystem | Virtual Repo URL |
|-----------|-----------------|
| npm | `$JFROG_URL/artifactory/api/npm/{virtual-key}/` |
| Maven | `$JFROG_URL/artifactory/{virtual-key}` |
| PyPI | `$JFROG_URL/artifactory/api/pypi/{virtual-key}/simple` |
| Go | `$JFROG_URL/artifactory/api/go/{virtual-key}` |
| Docker | `{jfrog-hostname}/{virtual-key}` (requires Docker registry port) |
| Helm | `$JFROG_URL/artifactory/{virtual-key}` |

## Get Repository

**Endpoint**: `GET /artifactory/api/repositories/{repo-key}`

## List Repositories

**Endpoint**: `GET /artifactory/api/repositories?project={project_key}`

Per the [JFrog docs](https://jfrog.com/help/r/jfrog-rest-apis/get-repositories-by-type-and-project), use `project` as the query parameter name. The list response does **not** include `projectKey` in its objects -- use the query parameter to filter server-side, or query individual repos via `GET /artifactory/api/repositories/{repo-key}` to see their `projectKey`.

## Delete Repository

**Endpoint**: `DELETE /artifactory/api/repositories/{repo-key}`
