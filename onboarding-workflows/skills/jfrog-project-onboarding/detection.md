# Language & Package Manager Detection

This document describes how to detect which package managers are used in a project.

## Detection Strategy

1. Search for indicator files in the repository root and subdirectories
2. Report all detected package managers to the user
3. Confirm which ones to set up before proceeding

## Supported Package Managers

### npm (Node.js/JavaScript)

**Indicator files**:
- `package.json` (primary)
- `package-lock.json`
- `yarn.lock`
- `pnpm-lock.yaml`

**Detection command**:
```bash
# Find package.json files
find . -name "package.json" -not -path "*/node_modules/*" 2>/dev/null
```

**What to look for in package.json**:
- `dependencies` - runtime dependencies
- `devDependencies` - development dependencies
- `scripts.build` - build commands
- `scripts.publish` - publish commands

### Docker

**Indicator files**:
- `Dockerfile` (primary)
- `docker-compose.yml`
- `docker-compose.yaml`
- `.dockerignore`

**Detection command**:
```bash
# Find Dockerfile and docker-compose files
find . -name "Dockerfile" -o -name "docker-compose.yml" -o -name "docker-compose.yaml" 2>/dev/null
```

**What to look for**:
- Base image in `FROM` instruction
- Multi-stage builds
- Image name patterns

### Maven (Java)

**Indicator files**:
- `pom.xml` (primary)
- `.mvn/` directory
- `mvnw` (Maven wrapper)

**Detection command**:
```bash
find . -name "pom.xml" -not -path "*/target/*" 2>/dev/null
```

**What to look for in pom.xml**:
- `<dependencies>` - project dependencies
- `<distributionManagement>` - artifact publishing config
- `<repositories>` - custom repository definitions

### pip (Python)

**Indicator files**:
- `requirements.txt` (primary)
- `pyproject.toml`
- `setup.py`
- `setup.cfg`
- `Pipfile`

**Detection command**:
```bash
find . -name "requirements.txt" -o -name "pyproject.toml" -o -name "setup.py" -o -name "Pipfile" 2>/dev/null
```

**What to look for**:
- Package dependencies in `requirements.txt`
- Build system config in `pyproject.toml`
- Upload/publish configuration

### Go

**Indicator files**:
- `go.mod` (primary)
- `go.sum`

**Detection command**:
```bash
find . -name "go.mod" 2>/dev/null
```

**What to look for in go.mod**:
- `module` directive (module path)
- `require` directives (dependencies)
- Private module paths

### Helm

**Indicator files**:
- `Chart.yaml` (primary)
- `values.yaml`
- `charts/` directory
- `templates/` directory with `.yaml` files

**Detection command**:
```bash
find . -name "Chart.yaml" 2>/dev/null
```

**What to look for in Chart.yaml**:
- `name` - chart name
- `version` - chart version
- `dependencies` - chart dependencies

## Detection Output

After scanning, report findings to the user:

```
I detected the following package managers in your project:

 npm
  - Found: package.json
  - Dependencies: 45 packages
  - Location: ./

 Docker
  - Found: Dockerfile, docker-compose.yml
  - Base image: node:18-alpine
  - Location: ./

 Maven
  - Found: pom.xml
  - Location: ./backend/

Would you like me to set up JFrog repositories for all of these?
```

## Handling Multiple Locations

If indicator files are found in multiple directories (monorepo pattern):

```
I detected npm in multiple locations:

1. ./frontend/package.json
2. ./backend/package.json
3. ./shared/package.json

These can all use the same JFrog npm repository. Proceed?
```

## No Detection

If no supported package managers are detected:

```
I couldn't automatically detect any supported package managers.

Supported: npm, Docker, Maven, pip, Go, Helm

Would you like to manually specify which package types to set up?
```

## Package Manager Reference

| Package Manager | Indicator Files | Registry URL |
|-----------------|-----------------|--------------|
| npm | `package.json` | `https://registry.npmjs.org` |
| Docker | `Dockerfile` | `https://registry-1.docker.io` |
| Maven | `pom.xml` | `https://repo1.maven.org/maven2` |
| PyPI | `requirements.txt`, `pyproject.toml` | `https://pypi.org` |
| Go | `go.mod` | `https://proxy.golang.org` |
| Helm | `Chart.yaml` | N/A (OCI or HTTP) |
| NuGet | `*.csproj`, `packages.config` | `https://api.nuget.org/v3/index.json` |
