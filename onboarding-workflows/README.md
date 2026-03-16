# Onboarding Workflows

Orchestrate JFrog Platform onboarding and GitHub repository configuration for multiple projects. Use manifest-driven, interactive, or reconcile flows to provision projects, create repos, add members, configure OIDC, and update CI.

## Who is this for?

**Suggested persona:** Platform admins, SRE, and anyone automating onboarding. Use this example when you need to provision JFrog projects and repos from a manifest, wire GitHub repos to Artifactory, or reconcile existing state with a desired configuration.

## What this does

Skills, rules, and templates in this example let you onboard one or more projects to the JFrog Platform.

- **Provision JFrog projects** and create Artifactory repositories (local, remote, virtual) for npm, Maven, PyPI, Go, Docker, and Helm
- **Custom repository definitions** — additional repos or overrides via smart merge with ecosystem-generated trios
- **Configure Xray indexing** and **Curation** on repositories (global defaults with per-project overrides)
- **Manage project members** — add users and groups with role-based access
- **Configure OIDC** — secretless CI authentication via OpenID Connect
- **Configure package managers** and **CI workflows** in remote GitHub repos
- **Persist manifests** to Artifactory or git (configurable via `state.destination`) for audit and reconciliation
- **Reconcile changes** — diff a manifest against live JFrog state and apply only the delta

## Prerequisites

| Tool | Install |
|------|---------|
| [Git](https://git-scm.com/) | Pre-installed or `brew install git` |
| [yq](https://github.com/mikefarah/yq) | `brew install yq` |
| [jq](https://stedolan.github.io/jq/) | `brew install jq` |

**Note:** The rules in this example instruct the agent **not** to use the JFrog CLI (`jf`). Instead, the agent uses direct REST API calls to the JFrog Platform. This keeps the setup simple and avoids the operational burden of installing and configuring the CLI when running onboarding from an IDE or automation environment.

### Credentials

Set `JFROG_URL` and `JFROG_ACCESS_TOKEN` (or use a `.env` file in the repository root). The token **must** be a Platform Admin token. Generate one from: `{jfrog-url}/ui/admin/configuration/security/access_tokens`

Ensure local git has access to target GitHub repos (SSH keys or credential helper).

## Quick start

### Option 1: Manifest-driven (recommended)

1. Copy and fill in the manifest:
   ```bash
   cp onboarding-workflows/templates/manifest-template.yaml my-manifest.yaml
   ```
2. Copy this example's `skills/` and `rules/` into your IDE (see main [README](../README.md)), then ask:
   > "Onboard all projects from my-manifest.yaml"

### Option 2: Interactive

Ask:
> "Onboard my GitHub repos to JFrog"

The agent collects project details interactively, builds a manifest, and runs the onboarding chain.

### Option 3: Reconcile / update

> "Update JFrog from my manifest" or "Reconcile manifest changes"

The agent loads the latest manifest from the configured state backend, diffs against live state, and applies only changes.

## Manifest format

The manifest YAML is the single source of truth. See **[templates/manifest-template.yaml](templates/manifest-template.yaml)** for the full schema.

## Supported ecosystems

| Ecosystem | Config file | CI commands |
|-----------|-------------|-------------|
| npm | `.npmrc` | `jf npm install`, `jf npm publish` |
| Maven | `.mvn/settings.xml` | `jf mvn install`, `jf mvn deploy` |
| pip | `pip.conf` | `jf pip install`, `jf rt upload` |
| Go | `GOPROXY` env var | `jf go build`, `jf go publish` |
| Docker | `docker login` | `jf docker push`, `jf docker scan` |
| Helm | `helm repo add` | `helm package`, `jf rt upload` |

## Skills reference

All skills are under `skills/`. Each directory has a `SKILL.md`.

| Skill | Purpose |
|-------|---------|
| `jfrog-project-onboarding` | Master orchestration — chains all skills; manifest-driven, interactive, and reconcile modes |
| `jfrog-provision-project` | Create JFrog projects via REST API |
| `jfrog-create-repos` | Create repos from ecosystems, custom definitions, or both (smart merge); Xray and Curation |
| `jfrog-manage-members` | Add users/groups to projects with roles |
| `jfrog-create-users-groups` | Create missing users and groups on the platform |
| `jfrog-oidc-setup` | Configure OIDC provider and identity mappings for secretless CI |
| `jfrog-delete-project` | Safely delete projects and associated repos |
| `jfrog-system-config-repo` | Persist and retrieve manifests via Artifactory or git |
| `jfrog-reconcile-manifest` | Diff manifest vs live state and apply only changes |
| `github-configure-package-managers` | Update package manager configs in GitHub repos |
| `github-configure-ci-workflows` | Modify GitHub Actions for Artifactory (OIDC or secrets) |
| `detect-existing-patterns` | Detect naming patterns on JFrog; user chooses convention |
| `jfrog-curation-onboarding` | Set up Curation policies (Block Malicious + 7 dry-run) |

## CI authentication

Two methods, via `github.oidc_setup` in the manifest:

**OIDC (secretless)** — Enterprise X or Enterprise+:
```yaml
- uses: jfrog/setup-jfrog-cli@v4
  env:
    JF_URL: ${{ vars.JF_URL }}
  with:
    oidc-provider-name: github-oidc
```

**Token-based** — any subscription:
```yaml
- uses: jfrog/setup-jfrog-cli@v4
  env:
    JF_URL: ${{ vars.JF_URL }}
    JF_ACCESS_TOKEN: ${{ secrets.JF_ACCESS_TOKEN }}
```

## Structure

```
onboarding-workflows/
├── README.md           # This file
├── rules/              # Example-specific rules
├── skills/             # All onboarding skills
├── templates/          # Manifest template, repo JSONs, workflows
└── scripts/            # detect-ecosystem.sh, validate-config.sh
```

## Related examples

- **platform-features** — JFrog Artifactory, Access, Curation, and related APIs used by these workflows.
- **compliance-and-policies** — Lifecycle and evidence policies; separate from project/repo onboarding.
