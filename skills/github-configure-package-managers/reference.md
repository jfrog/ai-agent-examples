# Package Manager Configuration Reference

## npm

### .npmrc (project-level)

```ini
# Resolve all packages from Artifactory virtual repo
registry=https://{{JFROG_HOSTNAME}}/artifactory/api/npm/{{PROJECT_KEY}}-npm/

# Auth token (developers set this locally or via env var)
//{{JFROG_HOSTNAME}}/artifactory/api/npm/{{PROJECT_KEY}}-npm/:_authToken=${JFROG_NPM_TOKEN}
always-auth=true
```

### Scoped packages

If only scoped packages should come from Artifactory:
```ini
@myorg:registry=https://{{JFROG_HOSTNAME}}/artifactory/api/npm/{{PROJECT_KEY}}-npm/
//{{JFROG_HOSTNAME}}/artifactory/api/npm/{{PROJECT_KEY}}-npm/:_authToken=${JFROG_NPM_TOKEN}
```

### Developer setup

Developers generate their token:
```bash
# Using JFrog CLI
jf npmc --repo-resolve {{PROJECT_KEY}}-npm --repo-deploy {{PROJECT_KEY}}-npm-local

# Or manually
curl -u username:password "$JFROG_URL/artifactory/api/npm/auth" >> ~/.npmrc
```

---

## Maven

### .mvn/settings.xml

```xml
<?xml version="1.0" encoding="UTF-8"?>
<settings xmlns="http://maven.apache.org/SETTINGS/1.2.0"
          xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
          xsi:schemaLocation="http://maven.apache.org/SETTINGS/1.2.0
            https://maven.apache.org/xsd/settings-1.2.0.xsd">

  <servers>
    <server>
      <id>artifactory</id>
      <!-- Developers set these via env vars or ~/.m2/settings.xml -->
      <username>${env.JFROG_USER}</username>
      <password>${env.JFROG_PASSWORD}</password>
    </server>
  </servers>

  <mirrors>
    <mirror>
      <id>artifactory</id>
      <name>JFrog Artifactory</name>
      <url>https://{{JFROG_HOSTNAME}}/artifactory/{{PROJECT_KEY}}-maven</url>
      <mirrorOf>*</mirrorOf>
    </mirror>
  </mirrors>

  <profiles>
    <profile>
      <id>artifactory</id>
      <repositories>
        <repository>
          <id>central</id>
          <url>https://{{JFROG_HOSTNAME}}/artifactory/{{PROJECT_KEY}}-maven</url>
          <snapshots><enabled>true</enabled></snapshots>
          <releases><enabled>true</enabled></releases>
        </repository>
      </repositories>
      <pluginRepositories>
        <pluginRepository>
          <id>central</id>
          <url>https://{{JFROG_HOSTNAME}}/artifactory/{{PROJECT_KEY}}-maven</url>
          <snapshots><enabled>true</enabled></snapshots>
          <releases><enabled>true</enabled></releases>
        </pluginRepository>
      </pluginRepositories>
    </profile>
  </profiles>

  <activeProfiles>
    <activeProfile>artifactory</activeProfile>
  </activeProfiles>
</settings>
```

### Maven Wrapper integration

If the project uses `.mvn/`, place `settings.xml` inside `.mvn/` and reference it:
```bash
mvn -s .mvn/settings.xml clean install
```

Or set in `.mvn/maven.config`:
```
-s .mvn/settings.xml
```

---

## pip (Python)

### pip.conf (project-level)

```ini
[global]
index-url = https://{username}:{password}@{{JFROG_HOSTNAME}}/artifactory/api/pypi/{{PROJECT_KEY}}-pypi/simple
trusted-host = {{JFROG_HOSTNAME}}
```

### pyproject.toml (Poetry)

```toml
[[tool.poetry.source]]
name = "artifactory"
url = "https://{{JFROG_HOSTNAME}}/artifactory/api/pypi/{{PROJECT_KEY}}-pypi/simple"
priority = "primary"
```

### Developer setup

```bash
# Configure pip globally
pip config set global.index-url "https://$JFROG_USER:$JFROG_PASSWORD@{{JFROG_HOSTNAME}}/artifactory/api/pypi/{{PROJECT_KEY}}-pypi/simple"

# Or use JFrog CLI
jf pipc --repo-resolve {{PROJECT_KEY}}-pypi --repo-deploy {{PROJECT_KEY}}-pypi-local
```

---

## Go

### Environment variables

```bash
export GOPROXY="https://${JFROG_USER}:${JFROG_PASSWORD}@{{JFROG_HOSTNAME}}/artifactory/api/go/{{PROJECT_KEY}}-go,direct"
export GONOSUMDB="github.com/myorg/*"
export GOFLAGS="-mod=mod"
```

### Developer setup

```bash
# Using JFrog CLI
jf goc --repo-resolve {{PROJECT_KEY}}-go --repo-deploy {{PROJECT_KEY}}-go-local

# Or set env vars in shell profile
echo 'export GOPROXY="https://..."' >> ~/.bashrc
```

---

## Docker

Docker does not use a project-level config file. Instead:

### Developer setup

```bash
# Login to Artifactory Docker registry
docker login {{JFROG_HOSTNAME}}

# Pull through virtual repo
docker pull {{JFROG_HOSTNAME}}/{{PROJECT_KEY}}-docker/library/nginx:latest

# Push to local repo
docker tag myimage:latest {{JFROG_HOSTNAME}}/{{PROJECT_KEY}}-docker-local/myimage:latest
docker push {{JFROG_HOSTNAME}}/{{PROJECT_KEY}}-docker-local/myimage:latest
```

### PR documentation

When onboarding Docker, add a `DOCKER.md` or update `README.md` with login and push/pull instructions.

---

## Helm

Helm does not use a project-level config file. Instead:

### Developer setup

```bash
# Add Artifactory Helm repository
helm repo add {{PROJECT_KEY}} https://{{JFROG_HOSTNAME}}/artifactory/{{PROJECT_KEY}}-helm --username $JFROG_USER --password $JFROG_PASSWORD
helm repo update

# Search for charts
helm search repo {{PROJECT_KEY}}/

# Install a chart from Artifactory
helm install my-release {{PROJECT_KEY}}/my-chart

# Package and upload a chart
helm package .
curl -u $JFROG_USER:$JFROG_PASSWORD -T my-chart-0.1.0.tgz \
  "https://{{JFROG_HOSTNAME}}/artifactory/{{PROJECT_KEY}}-helm-local/my-chart-0.1.0.tgz"
```

### Using JFrog CLI

```bash
# Upload a Helm chart
jf rt upload "*.tgz" "{{PROJECT_KEY}}-helm-local/" --flat=false

# Download a chart
jf rt download "{{PROJECT_KEY}}-helm/my-chart-0.1.0.tgz" .
```

### PR documentation

When onboarding Helm, add a `HELM.md` or update `README.md` with repo add and push/pull instructions.
