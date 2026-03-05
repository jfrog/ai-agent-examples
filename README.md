# JFrog AI Agent Skills & Rules

**Give your AI coding assistant deep knowledge of the JFrog Platform -- APIs, CLI, onboarding workflows, and architectural patterns.**

> **Disclaimer** -- This repository is a collection of community examples and is **not** a formal JFrog product. It is provided as-is to help users interact with the JFrog Platform and its features. No official support or warranty is provided. Use at your own discretion.

Skills work with **Cursor**, **VS Code + GitHub Copilot**, **Claude Code**, **Windsurf**, **Cline**, and [other agents](https://npmjs.com/package/skills#supported-agents) that support the open [Agent Skills](https://agentskills.io) format.

---

## What Are Skills & Rules?

**Skills** are agent instruction files (`SKILL.md`) that teach AI coding assistants how to perform JFrog Platform operations. Instead of reading docs, ask your agent in plain English:

> *"Set up a CI integration with security scans for my npm project"*
>
> *"Onboard my GitHub repos to JFrog"*
>
> *"Create a promotion policy that requires SLSA provenance evidence"*
>
> *"Check if lodash@4.17.20 has any critical vulnerabilities"*

**Rules** (`.mdc` files) are behavioral modifiers that shape how the agent interacts with you and the JFrog Platform (e.g., asking one question at a time, safe API call patterns).

---

## Available Skills

### Platform API & CLI Skills

Core skills providing deep knowledge of JFrog REST APIs, CLI commands, and architectural patterns.

| Skill | Triggers when you mention... |
|-------|------------------------------|
| **[jfrog-artifactory](skills/jfrog-artifactory/)** | artifactory, repository, artifact, deploy, docker registry, build info, AQL, replication, federation |
| **[jfrog-security](skills/jfrog-security/)** | xray, vulnerability, CVE, scan, policy, watch, violation, SBOM, SAST, secrets detection |
| **[jfrog-access](skills/jfrog-access/)** | access token, permission, user, group, project, authentication, RBAC |
| **[jfrog-distribution](skills/jfrog-distribution/)** | distribution, release bundle, promote, environment, edge node, release lifecycle, evidence |
| **[jfrog-curation](skills/jfrog-curation/)** | curation, package firewall, blocked package, curated repository, waiver, supply chain |
| **[jfrog-apptrust](skills/jfrog-apptrust/)** | apptrust, application entity, application version, trusted release, promote version, rollback |
| **[jfrog-runtime](skills/jfrog-runtime/)** | runtime, runtime cluster, running images, runtime sensor, container monitoring, node health |
| **[jfrog-mission-control](skills/jfrog-mission-control/)** | mission control, JPD, platform deployment, license, proxy, deployment health |
| **[jfrog-workers](skills/jfrog-workers/)** | worker, serverless, event hook, TypeScript worker, BEFORE_DOWNLOAD, custom logic |
| **[jfrog-cli](skills/jfrog-cli/)** | jf command, jfrog cli, jf rt, jf audit, jf scan, jf docker, file spec |
| **[jfrog-patterns](skills/jfrog-patterns/)** | pattern, best practice, architecture, get started, CI integration, multi-site, AppTrust |

### Onboarding & Provisioning Skills

Workflow skills for automating JFrog Platform onboarding, project provisioning, and GitHub integration.

| Skill | Purpose |
|-------|---------|
| **[jfrog-project-onboarding](skills/jfrog-project-onboarding/)** | Master orchestration -- chains all onboarding skills, supports manifest-driven, interactive, and reconcile modes |
| **[jfrog-provision-project](skills/jfrog-provision-project/)** | Create JFrog projects via REST API |
| **[jfrog-create-repos](skills/jfrog-create-repos/)** | Create repos from ecosystems, custom definitions, or both (smart merge), with Xray and Curation |
| **[jfrog-manage-members](skills/jfrog-manage-members/)** | Add users and groups to projects with role assignments |
| **[jfrog-create-users-groups](skills/jfrog-create-users-groups/)** | Create missing users and groups on the platform |
| **[jfrog-oidc-setup](skills/jfrog-oidc-setup/)** | Configure OIDC provider and identity mappings for secretless CI |
| **[jfrog-delete-project](skills/jfrog-delete-project/)** | Safely delete projects and all associated repos |
| **[jfrog-system-config-repo](skills/jfrog-system-config-repo/)** | Persist and retrieve manifests via Artifactory or git |
| **[jfrog-reconcile-manifest](skills/jfrog-reconcile-manifest/)** | Diff manifest against live JFrog state and apply only changes |
| **[jfrog-curation-onboarding](skills/jfrog-curation-onboarding/)** | Set up Curation policies (Block Malicious + dry-run policies) |
| **[detect-existing-patterns](skills/detect-existing-patterns/)** | Detect naming patterns in existing JFrog repos and let user choose |
| **[github-configure-package-managers](skills/github-configure-package-managers/)** | Update `.npmrc`, `settings.xml`, `pip.conf`, etc. in GitHub repos |
| **[github-configure-ci-workflows](skills/github-configure-ci-workflows/)** | Modify GitHub Actions for Artifactory integration (OIDC or secrets) |

### Compliance & Evidence Skills

Workflow skills for creating lifecycle policies that validate evidence before application promotion.

| Skill | Purpose |
|-------|---------|
| **[evidence-compliance-policies](skills/evidence-compliance-policies/)** | Create lifecycle policies that validate evidence (SLSA provenance, SonarQube, CycloneDX SBOM) before allowing promotion |

---

## Available Rules

Rules are organized by scope. Install only the rules relevant to your use case.

| Rule | Scope | Description |
|------|-------|-------------|
| [interaction-questions.mdc](rules/global/interaction-questions.mdc) | Global | Ask the user one question at a time |
| [jfrog-platform.mdc](rules/global/jfrog-platform.mdc) | Global | JFrog API conventions, auth patterns, safe `curl` usage, rate-limit protection |
| [onboarding-workflow.mdc](rules/onboarding/onboarding-workflow.mdc) | Onboarding | Skill chain order, state persistence, smart merge, reconciliation |
| [no-jfrog-cli.mdc](rules/onboarding/no-jfrog-cli.mdc) | Onboarding | Use REST API only (no `jf` CLI) -- **conflicts with Platform API skills that use CLI** |
| [mcp-usage-consent.mdc](rules/onboarding/mcp-usage-consent.mdc) | Onboarding | Do not use MCP for JFrog; use REST API only |
| [ignore-local-temp.mdc](rules/onboarding/ignore-local-temp.mdc) | Onboarding | Ignore `local/` and `temp/` directories |
| [jfrog-platform-conventions.mdc](rules/evidence/jfrog-platform-conventions.mdc) | Evidence | Template, rule, and policy naming conventions |
| [contributing.mdc](rules/contributing.mdc) | Development | Conventions for editing and creating skills |

> **Note:** The `no-jfrog-cli.mdc` onboarding rule instructs the agent to use only REST API calls. This conflicts with Platform API & CLI skills (like `jfrog-cli`) that require the JFrog CLI. Only install onboarding rules when using the onboarding skill group.

---

## Getting Started

### Prerequisites

| Requirement | Notes |
|-------------|-------|
| **JFrog Platform** | An active instance with the features needed by your chosen skills |
| **Access token** | With appropriate privileges (Platform Admin for onboarding skills) |
| **JFrog CLI** (`jf`) | Required for Platform API skills. Install via `brew install jfrog-cli` or the [official script](https://jfrog.com/help/r/jfrog-cli/install-the-jfrog-cli) |
| **curl + jq** | Required for onboarding and evidence skills |
| **yq** | Required for onboarding skills only (`brew install yq`) |

### Configuration

Copy the example environment file and fill in your credentials:

```bash
cp .env.example .env
```

Edit `.env` with your JFrog Platform URL and access token. The file is git-ignored to prevent credential exposure.

---

## Installation

Clone this repository first:

```bash
git clone https://github.com/jfrog/ai-agent-examples.git
cd ai-agent-examples
```

Then follow the instructions for your IDE or tool below.

### Cursor

Copy skills and rules into your project's `.cursor/` directory (or use `~/.cursor/` for global):

```bash
# Project-level (recommended)
TARGET_SKILLS=.cursor/skills
TARGET_RULES=.cursor/rules

mkdir -p "$TARGET_SKILLS" "$TARGET_RULES"

# Install all skills
for skill in skills/*/; do
  cp -R "$skill" "$TARGET_SKILLS/$(basename "$skill")"
done

# Install global rules (always recommended)
cp rules/global/*.mdc "$TARGET_RULES/"

# Install onboarding rules (only if using onboarding skills)
# cp rules/onboarding/*.mdc "$TARGET_RULES/"

# Install evidence rules (only if using evidence skills)
# cp rules/evidence/*.mdc "$TARGET_RULES/"
```

Or install specific skills:

```bash
cp -R skills/jfrog-artifactory .cursor/skills/
cp -R skills/jfrog-security .cursor/skills/
```

### VS Code + GitHub Copilot

GitHub Copilot reads instructions from `.github/copilot-instructions.md` and supports custom instructions. To use JFrog skills:

```bash
mkdir -p .github

# Copy skills into the project
cp -R skills .github/copilot-skills

# Add a reference to copilot instructions
cat >> .github/copilot-instructions.md << 'EOF'

## JFrog Skills

When working with JFrog Platform operations, refer to the skill files
in `.github/copilot-skills/` for API references, CLI commands, and workflows.
Each skill directory contains a SKILL.md with detailed instructions.
EOF
```

You can also configure Copilot custom instructions in VS Code settings to reference the skills directory.

### Claude Code

Claude Code supports skill files via the `CLAUDE.md` convention and the `/add-skill` command:

```bash
# Option 1: Symlink skills directory
ln -sf "$(pwd)/skills" ~/.claude/skills/jfrog

# Option 2: Reference in CLAUDE.md
cat >> CLAUDE.md << 'EOF'

## JFrog Skills

When performing JFrog Platform operations, read the relevant SKILL.md from
the skills/ directory for API references and workflow instructions.
Available skills: jfrog-artifactory, jfrog-security, jfrog-cli, jfrog-patterns, etc.
EOF
```

### Windsurf

Windsurf reads skills and rules from `.windsurf/`:

```bash
mkdir -p .windsurf/skills .windsurf/rules

# Install skills
for skill in skills/*/; do
  cp -R "$skill" ".windsurf/skills/$(basename "$skill")"
done

# Install global rules
cp rules/global/*.mdc .windsurf/rules/
```

### Cline (VS Code Extension)

Cline supports custom instructions and skill files:

```bash
mkdir -p .cline/skills

# Install skills
for skill in skills/*/; do
  cp -R "$skill" ".cline/skills/$(basename "$skill")"
done

# Add rules to .clinerules
cat rules/global/*.mdc >> .clinerules
```

### npx skills CLI (Multi-Agent)

The [`skills`](https://npmjs.com/package/skills) CLI can install skills directly from this repo for 37+ supported agents:

```bash
# Install all skills for all detected agents
npx skills add https://github.com/jfrog/ai-agent-examples.git --all

# Install all skills for a specific agent
npx skills add https://github.com/jfrog/ai-agent-examples.git --skill '*' -a cursor
npx skills add https://github.com/jfrog/ai-agent-examples.git --skill '*' -a claude-code
npx skills add https://github.com/jfrog/ai-agent-examples.git --skill '*' -a github-copilot
npx skills add https://github.com/jfrog/ai-agent-examples.git --skill '*' -a windsurf

# Install a specific skill
npx skills add https://github.com/jfrog/ai-agent-examples.git --skill jfrog-artifactory

# List available skills
npx skills add https://github.com/jfrog/ai-agent-examples.git --list

# Manage installed skills
npx skills remove     # interactive removal
npx skills check      # check for updates
npx skills update     # update all installed skills
```

> Add `-g` to install skills globally (available across all projects).

---

## Repository Structure

```
ai-agent-examples/
├── skills/                          # All agent skills
│   ├── jfrog-artifactory/           #   Platform API & CLI skills
│   ├── jfrog-security/
│   ├── jfrog-cli/
│   ├── jfrog-patterns/
│   ├── ...                          #   (11 platform skills total)
│   ├── jfrog-project-onboarding/    #   Onboarding & provisioning skills
│   ├── jfrog-create-repos/
│   ├── ...                          #   (13 onboarding skills total)
│   └── evidence-compliance-policies/#   Compliance & evidence skills
├── rules/                           # Agent behavior rules
│   ├── global/                      #   Rules for all skill usage
│   ├── onboarding/                  #   Rules for onboarding workflows only
│   └── evidence/                    #   Rules for evidence skills only
├── templates/                       # Onboarding manifest and repo templates
│   ├── manifest-template.yaml       #   Canonical manifest schema
│   ├── repos/                       #   JSON repo templates per ecosystem
│   ├── workflows/                   #   CI workflow templates
│   └── package-managers/            #   Package manager config templates
├── scripts/                         # Helper scripts
├── test/                            # Skill validation tests
├── .env.example                     # Environment variable template
├── CONTRIBUTING.md                  # How to add or update skills
└── LICENSE                          # MIT
```

Each skill directory contains:
- `SKILL.md` -- main agent instructions with YAML frontmatter
- Optional `*-reference.md` files -- API catalogs, command references
- Optional `assets/` -- example files, schemas, templates

---

## Data Sources

All skills are derived from public JFrog documentation and REST APIs:

- [JFrog Help Center](https://jfrog.com/help/home)
- [JFrog REST APIs](https://jfrog.com/help/r/jfrog-rest-apis)
- [JFrog CLI Documentation](https://jfrog.com/help/r/jfrog-cli)
- [Evidence Examples (GitHub)](https://github.com/jfrog/Evidence-Examples)

See [CONTRIBUTING.md](CONTRIBUTING.md) for the full data source catalog.

---

## Contributing

We welcome contributions of new skills, rules, and improvements. See [CONTRIBUTING.md](CONTRIBUTING.md) for:

- Skill format conventions and YAML frontmatter requirements
- Authentication and security rules
- How to add new skills or update existing ones
- The full data source catalog

---

## License

MIT -- see the [LICENSE](LICENSE) file for details.
