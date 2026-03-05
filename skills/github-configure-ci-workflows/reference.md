# CI Workflow Templates Reference

## JFrog Setup Step (common to all ecosystems)

### Secrets-based authentication

```yaml
# Add near the top of each job, before build steps
- name: Setup JFrog CLI
  uses: jfrog/setup-jfrog-cli@v4
  env:
    JF_URL: ${{ vars.JF_URL }}
    JF_ACCESS_TOKEN: ${{ secrets.JF_ACCESS_TOKEN }}
```

### OIDC authentication (used when subscription supports it)

```yaml
permissions:
  id-token: write
  contents: read

- name: Setup JFrog CLI
  uses: jfrog/setup-jfrog-cli@v4
  env:
    JF_URL: ${{ vars.JF_URL }}
  with:
    oidc-provider-name: {{OIDC_PROVIDER_NAME}}
```

Use the `oidc-provider-name` returned by the OIDC setup skill. When OIDC is configured, `JF_ACCESS_TOKEN` is **not** needed.

---

## npm Workflow

### With OIDC

```yaml
name: CI
on: [push, pull_request]

permissions:
  id-token: write
  contents: read

jobs:
  build:
    runs-on: ubuntu-latest
    env:
      JF_PROJECT: "{{PROJECT_KEY}}"
    steps:
      - uses: actions/checkout@v4

      - name: Setup Node.js
        uses: actions/setup-node@v4
        with:
          node-version: '20'

      - name: Setup JFrog CLI
        uses: jfrog/setup-jfrog-cli@v4
        env:
          JF_URL: ${{ vars.JF_URL }}
        with:
          oidc-provider-name: {{OIDC_PROVIDER_NAME}}

      - name: Configure npm
        run: jf npmc --repo-resolve {{PROJECT_KEY}}-npm --repo-deploy {{PROJECT_KEY}}-npm-local

      - name: Install dependencies
        run: jf npm install

      - name: Run tests
        run: npm test

      - name: Publish (if applicable)
        run: jf npm publish
        if: github.ref == 'refs/heads/main'
```

### With secrets

```yaml
name: CI
on: [push, pull_request]

permissions:
  contents: read

jobs:
  build:
    runs-on: ubuntu-latest
    env:
      JF_PROJECT: "{{PROJECT_KEY}}"
    steps:
      - uses: actions/checkout@v4

      - name: Setup Node.js
        uses: actions/setup-node@v4
        with:
          node-version: '20'

      - name: Setup JFrog CLI
        uses: jfrog/setup-jfrog-cli@v4
        env:
          JF_URL: ${{ vars.JF_URL }}
          JF_ACCESS_TOKEN: ${{ secrets.JF_ACCESS_TOKEN }}

      - name: Configure npm
        run: jf npmc --repo-resolve {{PROJECT_KEY}}-npm --repo-deploy {{PROJECT_KEY}}-npm-local

      - name: Install dependencies
        run: jf npm install

      - name: Run tests
        run: npm test

      - name: Publish (if applicable)
        run: jf npm publish
        if: github.ref == 'refs/heads/main'
```

---

## Maven Workflow

### With OIDC

```yaml
name: CI
on: [push, pull_request]

permissions:
  id-token: write
  contents: read

jobs:
  build:
    runs-on: ubuntu-latest
    env:
      JF_PROJECT: "{{PROJECT_KEY}}"
    steps:
      - uses: actions/checkout@v4

      - name: Setup Java
        uses: actions/setup-java@v4
        with:
          distribution: 'temurin'
          java-version: '17'

      - name: Setup JFrog CLI
        uses: jfrog/setup-jfrog-cli@v4
        env:
          JF_URL: ${{ vars.JF_URL }}
        with:
          oidc-provider-name: {{OIDC_PROVIDER_NAME}}

      - name: Configure Maven
        run: jf mvnc --repo-resolve-releases {{PROJECT_KEY}}-maven --repo-resolve-snapshots {{PROJECT_KEY}}-maven --repo-deploy-releases {{PROJECT_KEY}}-maven-local --repo-deploy-snapshots {{PROJECT_KEY}}-maven-local

      - name: Build and test
        run: jf mvn clean install

      - name: Deploy artifacts
        run: jf mvn deploy -DskipTests
        if: github.ref == 'refs/heads/main'
```

### With secrets

```yaml
name: CI
on: [push, pull_request]

permissions:
  contents: read

jobs:
  build:
    runs-on: ubuntu-latest
    env:
      JF_PROJECT: "{{PROJECT_KEY}}"
    steps:
      - uses: actions/checkout@v4

      - name: Setup Java
        uses: actions/setup-java@v4
        with:
          distribution: 'temurin'
          java-version: '17'

      - name: Setup JFrog CLI
        uses: jfrog/setup-jfrog-cli@v4
        env:
          JF_URL: ${{ vars.JF_URL }}
          JF_ACCESS_TOKEN: ${{ secrets.JF_ACCESS_TOKEN }}

      - name: Configure Maven
        run: jf mvnc --repo-resolve-releases {{PROJECT_KEY}}-maven --repo-resolve-snapshots {{PROJECT_KEY}}-maven --repo-deploy-releases {{PROJECT_KEY}}-maven-local --repo-deploy-snapshots {{PROJECT_KEY}}-maven-local

      - name: Build and test
        run: jf mvn clean install

      - name: Deploy artifacts
        run: jf mvn deploy -DskipTests
        if: github.ref == 'refs/heads/main'
```

---

## Python Workflow

### With OIDC

```yaml
name: CI
on: [push, pull_request]

permissions:
  id-token: write
  contents: read

jobs:
  build:
    runs-on: ubuntu-latest
    env:
      JF_PROJECT: "{{PROJECT_KEY}}"
    steps:
      - uses: actions/checkout@v4

      - name: Setup Python
        uses: actions/setup-python@v5
        with:
          python-version: '3.12'

      - name: Setup JFrog CLI
        uses: jfrog/setup-jfrog-cli@v4
        env:
          JF_URL: ${{ vars.JF_URL }}
        with:
          oidc-provider-name: {{OIDC_PROVIDER_NAME}}

      - name: Configure pip
        run: jf pipc --repo-resolve {{PROJECT_KEY}}-pypi --repo-deploy {{PROJECT_KEY}}-pypi-local

      - name: Install dependencies
        run: jf pip install -r requirements.txt

      - name: Run tests
        run: python -m pytest

      - name: Upload package
        run: |
          python -m build
          jf rt upload "dist/*" "{{PROJECT_KEY}}-pypi-local/"
        if: github.ref == 'refs/heads/main'
```

### With secrets

```yaml
name: CI
on: [push, pull_request]

permissions:
  contents: read

jobs:
  build:
    runs-on: ubuntu-latest
    env:
      JF_PROJECT: "{{PROJECT_KEY}}"
    steps:
      - uses: actions/checkout@v4

      - name: Setup Python
        uses: actions/setup-python@v5
        with:
          python-version: '3.12'

      - name: Setup JFrog CLI
        uses: jfrog/setup-jfrog-cli@v4
        env:
          JF_URL: ${{ vars.JF_URL }}
          JF_ACCESS_TOKEN: ${{ secrets.JF_ACCESS_TOKEN }}

      - name: Configure pip
        run: jf pipc --repo-resolve {{PROJECT_KEY}}-pypi --repo-deploy {{PROJECT_KEY}}-pypi-local

      - name: Install dependencies
        run: jf pip install -r requirements.txt

      - name: Run tests
        run: python -m pytest

      - name: Upload package
        run: |
          python -m build
          jf rt upload "dist/*" "{{PROJECT_KEY}}-pypi-local/"
        if: github.ref == 'refs/heads/main'
```

---

## Go Workflow

### With OIDC

```yaml
name: CI
on: [push, pull_request]

permissions:
  id-token: write
  contents: read

jobs:
  build:
    runs-on: ubuntu-latest
    env:
      JF_PROJECT: "{{PROJECT_KEY}}"
    steps:
      - uses: actions/checkout@v4

      - name: Setup Go
        uses: actions/setup-go@v5
        with:
          go-version: '1.22'

      - name: Setup JFrog CLI
        uses: jfrog/setup-jfrog-cli@v4
        env:
          JF_URL: ${{ vars.JF_URL }}
        with:
          oidc-provider-name: {{OIDC_PROVIDER_NAME}}

      - name: Configure Go
        run: jf goc --repo-resolve {{PROJECT_KEY}}-go --repo-deploy {{PROJECT_KEY}}-go-local

      - name: Build
        run: jf go build ./...

      - name: Test
        run: go test ./...

      - name: Publish module
        run: jf go publish v0.0.0
        if: github.ref == 'refs/heads/main'
```

### With secrets

```yaml
name: CI
on: [push, pull_request]

permissions:
  contents: read

jobs:
  build:
    runs-on: ubuntu-latest
    env:
      JF_PROJECT: "{{PROJECT_KEY}}"
    steps:
      - uses: actions/checkout@v4

      - name: Setup Go
        uses: actions/setup-go@v5
        with:
          go-version: '1.22'

      - name: Setup JFrog CLI
        uses: jfrog/setup-jfrog-cli@v4
        env:
          JF_URL: ${{ vars.JF_URL }}
          JF_ACCESS_TOKEN: ${{ secrets.JF_ACCESS_TOKEN }}

      - name: Configure Go
        run: jf goc --repo-resolve {{PROJECT_KEY}}-go --repo-deploy {{PROJECT_KEY}}-go-local

      - name: Build
        run: jf go build ./...

      - name: Test
        run: go test ./...

      - name: Publish module
        run: jf go publish v0.0.0
        if: github.ref == 'refs/heads/main'
```

---

## Docker Workflow

### With OIDC

```yaml
name: CI
on: [push, pull_request]

permissions:
  id-token: write
  contents: read

jobs:
  build:
    runs-on: ubuntu-latest
    env:
      JF_PROJECT: "{{PROJECT_KEY}}"
    steps:
      - uses: actions/checkout@v4

      - name: Setup JFrog CLI
        uses: jfrog/setup-jfrog-cli@v4
        env:
          JF_URL: ${{ vars.JF_URL }}
        with:
          oidc-provider-name: {{OIDC_PROVIDER_NAME}}

      - name: Authenticate Docker with Artifactory
        run: jf docker-login {{JFROG_HOSTNAME}}

      - name: Build Docker image
        run: docker build -t {{JFROG_HOSTNAME}}/{{PROJECT_KEY}}-docker-local/${{ github.event.repository.name }}:${{ github.sha }} .

      - name: Push Docker image
        run: jf docker push {{JFROG_HOSTNAME}}/{{PROJECT_KEY}}-docker-local/${{ github.event.repository.name }}:${{ github.sha }}
        if: github.ref == 'refs/heads/main'

      - name: Scan Docker image
        run: jf docker scan {{JFROG_HOSTNAME}}/{{PROJECT_KEY}}-docker-local/${{ github.event.repository.name }}:${{ github.sha }}
```

### With secrets

```yaml
name: CI
on: [push, pull_request]

permissions:
  contents: read

jobs:
  build:
    runs-on: ubuntu-latest
    env:
      JF_PROJECT: "{{PROJECT_KEY}}"
    steps:
      - uses: actions/checkout@v4

      - name: Setup JFrog CLI
        uses: jfrog/setup-jfrog-cli@v4
        env:
          JF_URL: ${{ vars.JF_URL }}
          JF_ACCESS_TOKEN: ${{ secrets.JF_ACCESS_TOKEN }}

      - name: Authenticate Docker with Artifactory
        run: jf docker-login {{JFROG_HOSTNAME}}

      - name: Build Docker image
        run: docker build -t {{JFROG_HOSTNAME}}/{{PROJECT_KEY}}-docker-local/${{ github.event.repository.name }}:${{ github.sha }} .

      - name: Push Docker image
        run: jf docker push {{JFROG_HOSTNAME}}/{{PROJECT_KEY}}-docker-local/${{ github.event.repository.name }}:${{ github.sha }}
        if: github.ref == 'refs/heads/main'

      - name: Scan Docker image
        run: jf docker scan {{JFROG_HOSTNAME}}/{{PROJECT_KEY}}-docker-local/${{ github.event.repository.name }}:${{ github.sha }}
```

---

## Helm Workflow

### With OIDC

```yaml
name: CI
on: [push, pull_request]

permissions:
  id-token: write
  contents: read

jobs:
  build:
    runs-on: ubuntu-latest
    env:
      JF_PROJECT: "{{PROJECT_KEY}}"
    steps:
      - uses: actions/checkout@v4

      - name: Setup Helm
        uses: azure/setup-helm@v4

      - name: Setup JFrog CLI
        uses: jfrog/setup-jfrog-cli@v4
        env:
          JF_URL: ${{ vars.JF_URL }}
        with:
          oidc-provider-name: {{OIDC_PROVIDER_NAME}}

      - name: Lint Helm chart
        run: helm lint .

      - name: Package Helm chart
        run: helm package .

      - name: Upload chart to Artifactory
        run: jf rt upload "*.tgz" "{{PROJECT_KEY}}-helm-local/" --flat=false
        if: github.ref == 'refs/heads/main'
```

### With secrets

```yaml
name: CI
on: [push, pull_request]

permissions:
  contents: read

jobs:
  build:
    runs-on: ubuntu-latest
    env:
      JF_PROJECT: "{{PROJECT_KEY}}"
    steps:
      - uses: actions/checkout@v4

      - name: Setup Helm
        uses: azure/setup-helm@v4

      - name: Setup JFrog CLI
        uses: jfrog/setup-jfrog-cli@v4
        env:
          JF_URL: ${{ vars.JF_URL }}
          JF_ACCESS_TOKEN: ${{ secrets.JF_ACCESS_TOKEN }}

      - name: Lint Helm chart
        run: helm lint .

      - name: Package Helm chart
        run: helm package .

      - name: Upload chart to Artifactory
        run: jf rt upload "*.tgz" "{{PROJECT_KEY}}-helm-local/" --flat=false
        if: github.ref == 'refs/heads/main'
```

---

## Build Command Mapping Quick Reference

| Ecosystem | Configure | Build/Install | Publish/Deploy |
|-----------|-----------|---------------|----------------|
| npm | `jf npmc --repo-resolve {v} --repo-deploy {l}` | `jf npm install` | `jf npm publish` |
| Maven | `jf mvnc --repo-resolve-releases {v} ...` | `jf mvn clean install` | `jf mvn deploy` |
| pip | `jf pipc --repo-resolve {v} --repo-deploy {l}` | `jf pip install -r requirements.txt` | `jf rt upload "dist/*" "{l}/"` |
| Go | `jf goc --repo-resolve {v} --repo-deploy {l}` | `jf go build ./...` | `jf go publish` |
| Docker | `jf docker-login {host}` | `docker build` | `jf docker push {host}/{l}/img:tag` |
| Helm | N/A | `helm package .` | `jf rt upload "*.tgz" "{l}/"` |

Legend: `{v}` = virtual repo, `{l}` = local repo
