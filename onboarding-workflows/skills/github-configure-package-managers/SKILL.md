---
name: github-configure-package-managers
description: Configure package manager settings in GitHub repositories to resolve dependencies from JFrog Artifactory. Handles npm (.npmrc), Maven (settings.xml), pip (pip.conf), Go (GOPROXY), Docker, and Helm. Use when setting up local developer dependency resolution through Artifactory.
---

# GitHub Configure Package Managers

Updates package manager configuration files in remote GitHub repositories so that developers resolve dependencies from Artifactory virtual repositories.

## Inputs

- `github_repos` -- list of owner/repo (e.g., `["myorg/my-app", "myorg/my-lib"]`)
- `project_key` -- JFrog project key (used in repo naming)
- `ecosystems` -- list from: `npm`, `maven`, `pip`, `go`, `docker`, `helm`
- `jfrog_url` -- JFrog Platform URL (from `$JFROG_URL`)
- `github_host` -- GitHub host URL (e.g., `https://github.com` or `https://github.mycompany.com`)

## Approach

For **each repo** in `github_repos`:

1. Shallow-clone the repo into a temp directory
2. Create a feature branch: `jfrog-onboarding`
3. Add/update the appropriate config files
4. Push the branch
5. Instruct the user to open a PR

### Cloning and creating a branch

```bash
GITHUB_HOST="https://github.com"  # or from manifest
REPO="owner/repo"                  # from github_repos[]
BRANCH_NAME="jfrog-onboarding"    # from manifest github.branch_name

TMPDIR=$(mktemp -d)
git clone --depth 1 "${GITHUB_HOST}/${REPO}.git" "$TMPDIR/repo"
cd "$TMPDIR/repo"
git checkout -b "$BRANCH_NAME"

# ... add/update config files ...

git add -A && git commit -m "chore: configure package managers for JFrog Artifactory"
git push -u origin "$BRANCH_NAME"
cd / && rm -rf "$TMPDIR"
```

After pushing, instruct the user:
> Branch `jfrog-onboarding` has been pushed to `{repo}`. Please open a PR to merge the package manager configuration changes.

## Per-Ecosystem Configuration

### npm
**File**: `.npmrc` (project root)
**Template**: `templates/package-managers/.npmrc`
```
registry=https://{jfrog-url}/artifactory/api/npm/{project-key}-npm/
//{jfrog-url}/artifactory/api/npm/{project-key}-npm/:_authToken=${JFROG_NPM_TOKEN}
always-auth=true
```

### Maven
**File**: `.mvn/settings.xml`
**Template**: `templates/package-managers/settings.xml`
- Configures `<mirror>` to point all repos to the Artifactory virtual
- Configures `<server>` with credential placeholders

### pip (Python)
**File**: `pip.conf` (project root)
**Template**: `templates/package-managers/pip.conf`
```
[global]
index-url = https://{username}:{password}@{jfrog-url}/artifactory/api/pypi/{project-key}-pypi/simple
```

### Go
**File**: `.env` or `README` update
**Template**: `templates/package-managers/go-env.sh`
```
export GOPROXY="https://{username}:{password}@{jfrog-url}/artifactory/api/go/{project-key}-go,direct"
export GONOSUMDB="github.com/myorg/*"
```

### Docker
No config file needed in the repo for authentication. However, **Dockerfiles should be updated** to pull base images through the JFrog virtual Docker repository.

#### Docker login instructions
Document in a `DOCKER.md` or commit message:
```
docker login {jfrog-hostname}
# Pull: docker pull {jfrog-hostname}/{project-key}-docker/image:tag
# Push: docker push {jfrog-hostname}/{project-key}-docker-local/image:tag
```

#### Dockerfile FROM rewriting

Find all Dockerfiles in the repository:

```bash
find . -type f \( -name "Dockerfile" -o -name "Dockerfile.*" -o -name "*.Dockerfile" \) 2>/dev/null
```

For each Dockerfile, update `FROM` directives to use the JFrog virtual Docker registry:

**Before** (pulling directly from Docker Hub):
```dockerfile
FROM node:18-alpine
FROM python:3.11-slim AS builder
FROM --platform=linux/amd64 ubuntu:22.04
```

**After** (pulling through JFrog proxy):
```dockerfile
FROM {jfrog-hostname}/{project-key}-docker/node:18-alpine
FROM {jfrog-hostname}/{project-key}-docker/python:3.11-slim AS builder
FROM --platform=linux/amd64 {jfrog-hostname}/{project-key}-docker/ubuntu:22.04
```

For multi-stage Dockerfiles, update **all** `FROM` statements.

To make the registry configurable via build arguments:
```dockerfile
ARG JFROG_REGISTRY={jfrog-hostname}/{project-key}-docker
FROM ${JFROG_REGISTRY}/node:18-alpine
```

**Benefits**: Faster builds (cached in Artifactory), reliability (no Docker Hub dependency), security scanning via Xray, audit trail, and consistent images across developers and CI.

Also update `docker-compose.yml` if present -- replace image references with JFrog registry paths:
```yaml
services:
  redis:
    image: {jfrog-hostname}/{project-key}-docker/redis:7-alpine
```

For detailed Docker configuration including multi-platform builds and troubleshooting, see [docker.md](../jfrog-create-repos/docker.md).

### Helm
No config file needed in the repo. Document in a `HELM.md` or commit message:
```
# Add Artifactory as a Helm repo
helm repo add {project-key} https://{jfrog-hostname}/artifactory/{project-key}-helm --username {username} --password {password}
helm repo update

# Install a chart from Artifactory
helm install my-release {project-key}/my-chart

# Push a chart to Artifactory
curl -u {username}:{password} -T my-chart-0.1.0.tgz "https://{jfrog-hostname}/artifactory/{project-key}-helm-local/my-chart-0.1.0.tgz"
```

## Template Substitution

Replace these placeholders in templates before committing:
- `{{JFROG_URL}}` -- JFrog Platform URL
- `{{JFROG_HOSTNAME}}` -- hostname portion only (no protocol)
- `{{PROJECT_KEY}}` -- JFrog project key
- `{{VIRTUAL_REPO}}` -- virtual repo key (e.g., `myproj-npm`)

## Additional Resources

For detailed per-ecosystem configuration options, see [reference.md](reference.md).
