---
name: github-configure-ci-workflows
description: Modify GitHub Actions workflows to resolve dependencies from JFrog Artifactory and upload build artifacts. Adds jfrog/setup-jfrog-cli action, replaces native build commands with JFrog CLI equivalents. Use when integrating CI/CD pipelines with JFrog or updating GitHub Actions for Artifactory.
---

# GitHub Configure CI Workflows

Modifies GitHub Actions workflow files in remote GitHub repositories to integrate with JFrog Artifactory for dependency resolution and artifact publishing.

## Inputs

- `github_repos` -- list of owner/repo (e.g., `["myorg/my-app", "myorg/my-lib"]`)
- `project_key` -- JFrog project key
- `ecosystems` -- list from: `npm`, `maven`, `pip`, `go`, `docker`, `helm`
- `oidc_provider_name` -- OIDC provider name from the OIDC setup skill (empty string if OIDC is not available)
- `github_host` -- GitHub host URL (e.g., `https://github.com` or `https://github.mycompany.com`)

## Workflow Modifications

### 1. Discover existing workflows

After cloning the repo, check for workflow files:

```bash
ls .github/workflows/ 2>/dev/null
```

If no workflows exist, create a new one based on the detected ecosystems.

### 2. Add JFrog CLI setup step

Insert the `jfrog/setup-jfrog-cli@v4` step early in each job, before any build steps.

**If OIDC is available** (`oidc_provider_name` is set):
```yaml
permissions:
  id-token: write
  contents: read

- name: Setup JFrog CLI
  uses: jfrog/setup-jfrog-cli@v4
  env:
    JF_URL: ${{ vars.JF_URL }}
  with:
    oidc-provider-name: {oidc_provider_name}
```

**If OIDC is NOT available** (secrets-based auth):
```yaml
- name: Setup JFrog CLI
  uses: jfrog/setup-jfrog-cli@v4
  env:
    JF_URL: ${{ vars.JF_URL }}
    JF_ACCESS_TOKEN: ${{ secrets.JF_ACCESS_TOKEN }}
```

Also set the project key:
```yaml
env:
  JF_PROJECT: "{project-key}"
```

### 3. Replace build commands

| Original | JFrog CLI Equivalent |
|----------|---------------------|
| `npm install` / `npm ci` | `jf npm install` |
| `npm publish` | `jf npm publish` |
| `mvn install` | `jf mvn install` |
| `mvn deploy` | `jf mvn deploy` |
| `pip install -r requirements.txt` | `jf pip install -r requirements.txt` |
| `go build` | `jf go build` |
| `go publish` | `jf go publish` |
| `docker build` | `docker build` (unchanged) |
| `docker push` | `jf docker push` |
| `helm package` | `helm package` (unchanged) |
| `helm push` / `curl -T` | `jf rt upload "*.tgz" "{project-key}-helm-local/"` |

### 4. Add artifact upload step (if not present)

```yaml
- name: Upload build artifacts
  run: jf rt upload "build-output/*" "{project-key}-{ecosystem}-local/"
```

### 5. Build info is auto-published

The `setup-jfrog-cli@v4` action auto-publishes build info at the end of the workflow. No explicit `jf rt build-publish` is needed.

## Approach: Sparse Clone

For **each repo** in `github_repos`, clone the repo, modify workflow files, push a feature branch, and instruct the user to open a PR.

```bash
GITHUB_HOST="https://github.com"  # or from manifest
REPO="owner/repo"                  # from github_repos[]
BRANCH_NAME="jfrog-onboarding"    # from manifest github.branch_name

TMPDIR=$(mktemp -d)
git clone --depth 1 "${GITHUB_HOST}/${REPO}.git" "$TMPDIR/repo"
cd "$TMPDIR/repo"

# Check if branch already exists (from package-manager step)
if git ls-remote --heads origin "$BRANCH_NAME" | grep -q "$BRANCH_NAME"; then
  git fetch origin "$BRANCH_NAME"
  git checkout "$BRANCH_NAME"
else
  git checkout -b "$BRANCH_NAME"
fi

# Edit workflow files in .github/workflows/
# ... (use the agent's editing capabilities)

git add -A && git commit -m "ci: integrate with JFrog Artifactory"
git push -u origin "$BRANCH_NAME"
cd / && rm -rf "$TMPDIR"
```

After pushing, instruct the user:
> Branch `jfrog-onboarding` has been pushed to `{repo}`. Please open a PR to merge these CI workflow changes.

## GitHub Repository Secrets Setup

Remind the user to set these in each target GitHub repo (Settings > Secrets and Variables):

**If using OIDC authentication:**
- **Variable**: `JF_URL` = `https://mycompany.jfrog.io`
- No secrets needed -- OIDC handles authentication

**If using secrets-based authentication:**
- **Variable**: `JF_URL` = `https://mycompany.jfrog.io`
- **Secret**: `JF_ACCESS_TOKEN` = JFrog access token for CI

## GitHub Enterprise: JFrog CLI Install Fallback

On self-hosted GitHub Enterprise runners, `jfrog/setup-jfrog-cli@v4` may not be available (e.g., restricted marketplace access or air-gapped environments). In these cases, install JFrog CLI directly via curl as a fallback:

```yaml
- name: Install JFrog CLI
  run: |
    # Download and install JFrog CLI directly
    curl -fL https://install-cli.jfrog.io | sh
    # Move to PATH
    sudo mv jf /usr/local/bin/jf
    jf --version

- name: Configure JFrog CLI
  run: |
    jf config add ci-server \
      --url="${{ vars.JF_URL }}" \
      --access-token="${{ secrets.JF_ACCESS_TOKEN }}" \
      --interactive=false
    jf config use ci-server
```

If the runner cannot reach `install-cli.jfrog.io`, download the JFrog CLI binary from your own Artifactory instance:

```yaml
- name: Install JFrog CLI (from Artifactory)
  run: |
    curl -fL -H "Authorization: Bearer ${{ secrets.JF_ACCESS_TOKEN }}" \
      "${{ vars.JF_URL }}/artifactory/jfrog-cli/v2-jf/[RELEASE]/jfrog-cli-linux-amd64/jf" \
      -o /usr/local/bin/jf
    chmod +x /usr/local/bin/jf
    jf --version
```

Use this fallback only when `jfrog/setup-jfrog-cli@v4` is unavailable. The GitHub Action is preferred because it handles caching, auto-publishes build info, and manages the CLI lifecycle.

## Additional Resources

For per-ecosystem workflow templates, see [reference.md](reference.md).
For GitHub secrets setup guide, see [github-secrets-setup.md](github-secrets-setup.md).
