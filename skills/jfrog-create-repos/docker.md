# Docker Configuration

This document describes how to set up JFrog repositories for Docker images and configure the local development environment.

## Required Tools

Before proceeding, verify these tools are installed:

```bash
# Check required tools
for tool in curl jq docker; do
  if ! command -v $tool &> /dev/null; then
    echo "ERROR: $tool is not installed"
  else
    echo "OK: $tool ($(command -v $tool))"
  fi
done

# Check Docker daemon is running
if ! docker info &> /dev/null; then
  echo "ERROR: Docker daemon is not running"
  echo "  Start Docker Desktop or run: sudo systemctl start docker"
fi
```

**Installation if missing:**

| Tool | macOS | Ubuntu/Debian | Purpose |
|------|-------|---------------|---------|
| curl | `brew install curl` | `sudo apt-get install curl` | API calls |
| jq | `brew install jq` | `sudo apt-get install jq` | JSON parsing |
| docker | [Docker Desktop](https://www.docker.com/products/docker-desktop/) | `sudo apt-get install docker.io` | Container operations |

## Repository Structure

For Docker, create three repositories:

| Repository | Type | Purpose |
|------------|------|---------|
| `{project}-docker-remote` | Remote | Proxies Docker Hub |
| `{project}-docker-local` | Local | Stores your built images |
| `{project}-docker` | Virtual | User-facing, aggregates both |

## Repository Creation

### 1. Remote Repository (Proxy)

Creates a cache/proxy to Docker Hub:

```bash
curl -X PUT "${JFROG_URL}/artifactory/api/repositories/${PROJECT_KEY}-docker-remote" \
  -H "Authorization: Bearer ${JFROG_ACCESS_TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{
    "key": "'${PROJECT_KEY}'-docker-remote",
    "rclass": "remote",
    "packageType": "docker",
    "url": "https://registry-1.docker.io",
    "projectKey": "'${PROJECT_KEY}'",
    "description": "Proxy cache for Docker Hub"
  }'
```

### 2. Local Repository (Push Target)

Stores your built Docker images:

```bash
curl -X PUT "${JFROG_URL}/artifactory/api/repositories/${PROJECT_KEY}-docker-local" \
  -H "Authorization: Bearer ${JFROG_ACCESS_TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{
    "key": "'${PROJECT_KEY}'-docker-local",
    "rclass": "local",
    "packageType": "docker",
    "projectKey": "'${PROJECT_KEY}'",
    "description": "Local repository for built Docker images"
  }'
```

### 3. Virtual Repository (User-Facing)

Aggregates local and remote -- developers use this registry:

```bash
curl -X PUT "${JFROG_URL}/artifactory/api/repositories/${PROJECT_KEY}-docker" \
  -H "Authorization: Bearer ${JFROG_ACCESS_TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{
    "key": "'${PROJECT_KEY}'-docker",
    "rclass": "virtual",
    "packageType": "docker",
    "repositories": ["'${PROJECT_KEY}'-docker-local", "'${PROJECT_KEY}'-docker-remote"],
    "defaultDeploymentRepo": "'${PROJECT_KEY}'-docker-local",
    "projectKey": "'${PROJECT_KEY}'",
    "description": "Virtual Docker registry - use this for pull and push"
  }'
```

## Docker Registry URL

The Docker registry URL format is:

```
{jfrog-host}/{repository-key}
```

**Example** for project `myapp` on `mycompany.jfrog.io`:

```
mycompany.jfrog.io/myapp-docker
```

## Local Development Configuration

### Docker Login

Authenticate with the JFrog Docker registry.

**Important:** Docker login requires both a **username** and **password/token**.

#### Ask for Username

If the user wants you to perform docker login, **ask for their JFrog username**:

> To log in to the JFrog Docker registry, I need your **JFrog username** (email or username).
>
> Please provide your JFrog username:

**Wait for the user to provide their username.**

#### Perform Docker Login

Once you have the username, perform the login:

```bash
# Load credentials from .env
if [ -z "$JFROG_URL" ] || [ -z "$JFROG_ACCESS_TOKEN" ]; then
  if [ -f .env ]; then set -a; source .env; set +a; fi
fi

JFROG_HOST="${JFROG_URL#https://}"

# Username provided by user
JFROG_USERNAME="user-provided-username"

# Login with access token
echo "${JFROG_ACCESS_TOKEN}" | docker login "${JFROG_HOST}" --username "${JFROG_USERNAME}" --password-stdin
```

#### If User Declines Login

If the user prefers to do it manually, provide the command with a placeholder:

> Run the following command to log in to JFrog Docker registry:
> ```bash
> echo "YOUR_TOKEN" | docker login {jfrog-host} --username YOUR_USERNAME --password-stdin
> ```
> Replace `YOUR_USERNAME` with your JFrog username and `YOUR_TOKEN` with your access token.

### Project-Level Docker Configuration

To keep Docker credentials at the project level, use the `DOCKER_CONFIG` environment variable:

```bash
# Create project-level docker config directory
mkdir -p .docker

# Set DOCKER_CONFIG to use project directory
export DOCKER_CONFIG="$(pwd)/.docker"

# Load credentials from .env
if [ -z "$JFROG_URL" ] || [ -z "$JFROG_ACCESS_TOKEN" ]; then
  if [ -f .env ]; then set -a; source .env; set +a; fi
fi

JFROG_HOST="${JFROG_URL#https://}"
JFROG_USERNAME="user-provided-username"

echo "${JFROG_ACCESS_TOKEN}" | docker login "${JFROG_HOST}" --username "${JFROG_USERNAME}" --password-stdin

# Add .docker/ to .gitignore
echo ".docker/" >> .gitignore
```

**Important**: Add `.docker/` to your `.gitignore` to avoid committing credentials.

## Usage

### Pulling Images

Pull images through JFrog (proxied from Docker Hub or local):

```bash
# Pull from Docker Hub through JFrog proxy
docker pull mycompany.jfrog.io/myapp-docker/nginx:latest

# Pull a locally published image
docker pull mycompany.jfrog.io/myapp-docker/myapp:1.0.0
```

### Building and Pushing Images

Build and push your images to JFrog:

```bash
# Build with JFrog registry tag
docker build -t mycompany.jfrog.io/myapp-docker/myapp:1.0.0 .

# Push to JFrog (goes to local repository via virtual)
docker push mycompany.jfrog.io/myapp-docker/myapp:1.0.0
```

### Updating Dockerfiles

**Important:** Update all Dockerfiles to use JFrog for base images. This ensures images are pulled through the JFrog virtual repository.

#### Find all Dockerfiles

```bash
# Find all Dockerfile variants in the project
find . -type f \( -name "Dockerfile" -o -name "Dockerfile.*" -o -name "*.Dockerfile" \) 2>/dev/null
```

#### Update FROM directives

For each Dockerfile, update the `FROM` directive to use the JFrog registry:

**Before** (pulling directly from Docker Hub):
```dockerfile
FROM node:18-alpine
FROM python:3.11-slim AS builder
FROM --platform=linux/amd64 ubuntu:22.04
```

**After** (pulling through JFrog proxy):
```dockerfile
FROM mycompany.jfrog.io/myapp-docker/node:18-alpine
FROM mycompany.jfrog.io/myapp-docker/python:3.11-slim AS builder
FROM --platform=linux/amd64 mycompany.jfrog.io/myapp-docker/ubuntu:22.04
```

#### Multi-stage builds

For multi-stage Dockerfiles, update ALL `FROM` statements:

```dockerfile
# Build stage
FROM mycompany.jfrog.io/myapp-docker/node:18-alpine AS builder
WORKDIR /app
COPY package*.json ./
RUN npm ci
COPY . .
RUN npm run build

# Production stage
FROM mycompany.jfrog.io/myapp-docker/nginx:alpine
COPY --from=builder /app/dist /usr/share/nginx/html
```

#### Using build arguments for flexibility

To make the registry configurable, use build arguments:

```dockerfile
ARG JFROG_REGISTRY=mycompany.jfrog.io/myapp-docker
FROM ${JFROG_REGISTRY}/node:18-alpine
```

Then build with:
```bash
docker build --build-arg JFROG_REGISTRY=mycompany.jfrog.io/myapp-docker .
```

#### Benefits of using JFrog for base images

- **Faster builds**: Images cached locally in Artifactory
- **Reliability**: No dependency on Docker Hub availability
- **Security**: Base images scanned by Xray for vulnerabilities
- **Compliance**: Audit trail of all images used
- **Consistency**: Same images across all developers and CI

## Image Naming Convention

Use consistent naming for your images:

```
{jfrog-host}/{virtual-repo}/{image-name}:{tag}
```

**Examples**:
```
mycompany.jfrog.io/myapp-docker/myapp:1.0.0
mycompany.jfrog.io/myapp-docker/myapp:latest
mycompany.jfrog.io/myapp-docker/myapp-api:1.0.0
mycompany.jfrog.io/myapp-docker/myapp-worker:1.0.0
```

## Docker Compose

Update `docker-compose.yml` to use JFrog:

```yaml
version: '3.8'
services:
  app:
    image: mycompany.jfrog.io/myapp-docker/myapp:${VERSION:-latest}
    build:
      context: .
      dockerfile: Dockerfile

  # External services through proxy
  redis:
    image: mycompany.jfrog.io/myapp-docker/redis:7-alpine

  postgres:
    image: mycompany.jfrog.io/myapp-docker/postgres:15-alpine
```

## Verification

### Test Pull (Proxy)

```bash
# Pull a public image through JFrog
docker pull mycompany.jfrog.io/myapp-docker/alpine:latest

# Verify it came from JFrog
docker inspect mycompany.jfrog.io/myapp-docker/alpine:latest | grep -i repotag
```

### Test Push

```bash
# Create a test image
echo "FROM alpine" | docker build -t mycompany.jfrog.io/myapp-docker/test:v1 -

# Push to JFrog
docker push mycompany.jfrog.io/myapp-docker/test:v1
```

### Verify Image in JFrog

After pushing, the image should appear in JFrog:

```bash
# List images in repository
curl -s -H "Authorization: Bearer ${JFROG_ACCESS_TOKEN}" \
  "${JFROG_URL}/artifactory/api/docker/${PROJECT_KEY}-docker-local/v2/_catalog"
```

## Multi-Platform Builds

For multi-platform images, use `docker buildx`:

```bash
# Create builder instance
docker buildx create --use

# Build and push multi-platform image
docker buildx build \
  --platform linux/amd64,linux/arm64 \
  -t mycompany.jfrog.io/myapp-docker/myapp:1.0.0 \
  --push \
  .
```

## Troubleshooting

| Issue | Solution |
|-------|----------|
| `unauthorized: authentication required` | Run `docker login` with correct credentials |
| `denied: requested access to the resource is denied` | Check token has push permissions |
| `manifest unknown` | Image doesn't exist in JFrog, check name/tag |
| `Error response from daemon: Get https://...` | Docker daemon can't reach JFrog, check network |
| Slow pulls | First pull caches in JFrog, subsequent pulls are faster |

### Check Docker Login Status

```bash
# If using project-level DOCKER_CONFIG
export DOCKER_CONFIG="$(pwd)/.docker"
cat "${DOCKER_CONFIG}/config.json" | jq '.auths'

# Should show your JFrog host
```

### Clear Docker Cache

```bash
# Remove cached images
docker system prune -a

# Clear buildx cache
docker buildx prune
```
