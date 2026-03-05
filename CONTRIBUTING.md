# Contributing to JFrog AI Agent Skills & Rules

This document covers skill and rule conventions, how to add or update content, and the catalog of public data sources.

## Repository layout

```
skills/<skill-name>/
  SKILL.md              # Required -- main agent instructions
  *-reference.md        # Optional -- API catalogs, command syntax
  assets/               # Optional -- example files, schemas

rules/
  global/               # Rules that apply to all skills
  onboarding/           # Rules specific to onboarding workflows
  evidence/             # Rules specific to evidence/compliance skills
  contributing.mdc      # Conventions for skill authoring
```

## Skill conventions

### Directory naming

- Platform skills: `skills/jfrog-<product>/` (e.g., `jfrog-artifactory`, `jfrog-security`)
- Workflow skills: `skills/jfrog-<action>/` or `skills/<descriptive-name>/` (e.g., `jfrog-project-onboarding`, `detect-existing-patterns`)

### YAML frontmatter

Every `SKILL.md` must start with YAML frontmatter:

```yaml
---
name: Human-readable skill name (e.g. JFrog Artifactory)
description: Use when working with ... Triggers on mentions of keyword1, keyword2, ...
---
```

- `name`: Short, product-aligned name.
- `description`: One or two sentences. Include a clear list of **trigger keywords** so the agent knows when to apply the skill.

### Recommended sections in SKILL.md

1. **Authentication** -- how to authenticate (CLI-based via `jf config` or REST-based via `$JFROG_ACCESS_TOKEN`)
2. **Pre-flight** (if applicable) -- ping the target service to confirm availability before proceeding
3. **Core workflow** -- step-by-step instructions the agent follows
4. **Parallelization** (if applicable) -- which operations can run concurrently
5. **Official Documentation** -- 2-5 links to relevant JFrog Help / REST API / CLI docs

### API and URL placeholders

Use `$JFROG_URL` in URL patterns (e.g., `$JFROG_URL/artifactory/api/...`). Never hardcode specific JFrog hostnames.

### Reference files

Name API and command catalogs with a `*-reference.md` suffix:
- `rest-api-reference.md` -- REST API endpoint summaries and curl examples
- `api-reference.md` -- shorter API reference
- `aql-reference.md`, `events-reference.md`, etc. -- product-specific references

Keep long catalogs in reference files so the main `SKILL.md` stays scannable.

## Rule conventions

Rules use the `.mdc` format with YAML frontmatter:

```yaml
---
description: What this rule does
alwaysApply: true
---
```

When adding a new rule:

1. Determine the scope -- does it apply globally or only to a specific skill group?
2. Place it in the appropriate subdirectory under `rules/` (`global/`, `onboarding/`, `evidence/`)
3. Keep rules focused on a single concern
4. Document the rule in the [Available Rules](README.md#available-rules) table in the README

## Security

Every skill interacts with authenticated JFrog Platform APIs. These rules apply to all skill content.

### Credential handling

- **Never print tokens.** Skill instructions must never `echo`, `cat`, or otherwise display access tokens in terminal output. Extract tokens silently into shell variables.
- **Never surface tokens in chat.** The agent must not repeat token values back to the user. Use phrases like "authenticated successfully" -- never the token itself.
- **Never hardcode tokens.** Use `$JFROG_ACCESS_TOKEN` in all examples.

### Shell safety

- **Quote all variables** in shell commands (`"${VAR}"`, not `$VAR`).
- **Avoid shell interpolation for secrets.** When passing tokens to scripts, use environment variables or stdin -- never inline `${VAR}` inside heredoc code.
- **Validate URLs before use.** Ping the server (`/artifactory/api/system/ping`) before using a user-provided URL in further API calls.

### Credential storage

- **`jf config` is the credential store** for Platform API skills. Tokens are encrypted at rest.
- **`.env` files** may be used for onboarding/workflow skills. Ensure `.env` is always in `.gitignore`.
- **Never store credentials in project files.** Tokens must never be written to the workspace or committed to version control.

### Review checklist for contributors

When adding or modifying a skill, verify:

1. No `echo`, `cat`, or `print()` of token values anywhere in the instructions.
2. All shell scripts use quoted variables and quoted heredocs for embedded scripts.
3. Credentials are stored only via `jf config` or `.env` -- no plaintext files.
4. No real tokens, passwords, or hostnames appear in examples.
5. URL validation (ping) precedes any authenticated API call to a new server.
6. Skills for non-Artifactory services include a pre-flight ping check.

## How to add a new skill

1. Create a directory under `skills/` following the naming convention above.
2. Add a `SKILL.md` with proper YAML frontmatter (`name` and `description` with trigger keywords).
3. Include an Authentication section.
4. Add reference files as needed (`*-reference.md`).
5. End with an Official Documentation section linking to relevant JFrog docs.
6. Update the skills table in [README.md](README.md).
7. Run the tests: `npm test`

## How to update a skill

1. **Identify the data source** -- use the [Data source catalog](#data-source-catalog) below.
2. **Refresh from the source** -- check the linked docs for new endpoints, parameters, or behavior.
3. **Update reference files first** -- if the change is in API details, update `*-reference.md`.
4. **Update SKILL.md if needed** -- if new capabilities change the high-level flow or triggers.
5. **Update this catalog** -- if you pull from a new doc URL, add it below.
6. **Test** -- ask your AI agent something that should trigger the skill and confirm the answer aligns.

## Running tests

```bash
npm test
```

Tests validate that every skill directory has:
- A `SKILL.md` file
- YAML frontmatter with `name` and `description`
- Non-empty Markdown files
- No hardcoded JFrog hostnames

For `jfrog-*` skills, additional checks ensure trigger keywords, Authentication sections, and Documentation sections are present.

---

## Data source catalog

All skills are derived from public JFrog documentation. Use this list to refresh skills when JFrog docs or APIs change.

### jfrog-artifactory

| URL | Feeds into |
|-----|------------|
| https://jfrog.com/help/r/jfrog-rest-apis/artifactory-rest-apis | rest-api-reference.md |
| https://jfrog.com/help/r/jfrog-artifactory-documentation/repository-management | SKILL.md, rest-api-reference.md |
| https://jfrog.com/help/r/jfrog-artifactory-documentation/federated-repositories | SKILL.md |
| https://jfrog.com/help/r/jfrog-artifactory-documentation/using-aql | aql-reference.md |
| Package-type registry URLs (Docker, Maven, npm, PyPI, Go, Helm, NuGet, Terraform, Cargo, Conan, Pub, etc.) | package-types-reference.md |

### jfrog-security

| URL | Feeds into |
|-----|------------|
| https://jfrog.com/help/r/xray-rest-apis | xray-api-reference.md |
| https://jfrog.com/help/r/jfrog-security-user-guide/products/xray | SKILL.md, scanning-guide.md |
| https://jfrog.com/help/r/jfrog-security-user-guide/products/advanced-security | SKILL.md |
| https://jfrog.com/help/r/jfrog-security-user-guide/products/runtime | SKILL.md |
| https://jfrog.com/help/r/jfrog-security-user-guide/products/runtime/apis | SKILL.md |

### jfrog-access

| URL | Feeds into |
|-----|------------|
| https://jfrog.com/help/r/jfrog-rest-apis/access-tokens | api-reference.md |
| https://jfrog.com/help/r/jfrog-rest-apis/permissions | api-reference.md |
| https://jfrog.com/help/r/jfrog-platform-administration-documentation/projects | SKILL.md |
| https://jfrog.com/help/r/jfrog-platform-administration-documentation/access-federation | SKILL.md |
| https://jfrog.com/help/r/jfrog-rest-apis/get-project-environments | SKILL.md |

### jfrog-distribution

| URL | Feeds into |
|-----|------------|
| https://jfrog.com/help/r/jfrog-rest-apis/distribution-rest-apis | api-reference.md |
| https://jfrog.com/help/r/jfrog-artifactory-documentation/release-lifecycle-management | SKILL.md, api-reference.md |
| https://jfrog.com/help/r/jfrog-artifactory-documentation/evidence-management | SKILL.md |
| https://jfrog.com/help/r/jfrog-artifactory-documentation/create-evidence-using-rest-apis | SKILL.md |
| https://jfrog.com/help/r/jfrog-rest-apis/prepare-evidence | SKILL.md |
| https://github.com/jfrog/Evidence-Examples | SKILL.md, api-reference.md |

### jfrog-apptrust

| URL | Feeds into |
|-----|------------|
| https://jfrog.com/help/r/jfrog-rest-apis/apptrust-rest-apis | SKILL.md, api-reference.md |
| https://jfrog.com/help/r/jfrog-security-documentation/jfrog-apptrust | SKILL.md |

### jfrog-curation

| URL | Feeds into |
|-----|------------|
| https://jfrog.com/help/r/jfrog-security-user-guide/products/curation | SKILL.md |
| https://jfrog.com/curation | SKILL.md |

### jfrog-mission-control

| URL | Feeds into |
|-----|------------|
| https://jfrog.com/help/r/jfrog-rest-apis/mission-control | SKILL.md, api-reference.md |
| https://jfrog.com/help/r/jfrog-platform-administration-documentation/mission-control | SKILL.md |

### jfrog-runtime

| URL | Feeds into |
|-----|------------|
| https://jfrog.com/help/r/jfrog-security-user-guide/products/runtime | SKILL.md |
| https://jfrog.com/help/r/jfrog-security-user-guide/products/runtime/apis | SKILL.md, api-reference.md |

### jfrog-workers

| URL | Feeds into |
|-----|------------|
| https://jfrog.com/help/r/jfrog-platform-administration-documentation/workers | SKILL.md |
| https://jfrog.com/help/r/jfrog-platform-administration-documentation/typescript-code-for-workers | SKILL.md |
| https://jfrog.com/help/r/jfrog-rest-apis/create-worker | SKILL.md, api-reference.md |
| https://jfrog.com/help/r/jfrog-platform-administration-documentation/supported-worker-events | events-reference.md |

### jfrog-cli

| URL | Feeds into |
|-----|------------|
| https://jfrog.com/help/r/jfrog-cli | SKILL.md |
| https://jfrog.com/help/r/jfrog-cli/cli-for-jfrog-artifactory | artifactory-commands.md |
| https://jfrog.com/help/r/jfrog-cli/cli-for-jfrog-security | security-commands.md |
| https://github.com/jfrog/documentation/blob/main/SUMMARY.md | platform-commands.md |
| https://github.com/jfrog/jfrog-cli (login flow) | login-flow.md |

### jfrog-patterns

| URL or source | Feeds into |
|---------------|------------|
| https://jfrog.com/help/r/jfrog-integrations-documentation/build-integration | ci-integration.md |
| https://jfrog.com/help/r/jfrog-artifactory-documentation/repository-management | repositories.md |
| https://jfrog.com/help/r/jfrog-artifactory-documentation/release-lifecycle-management | release-lifecycle.md |
| https://jfrog.com/help/r/jfrog-artifactory-documentation/evidence-management | release-lifecycle.md, ci-integration.md |
| https://jfrog.com/help/r/jfrog-security-user-guide/products/xray | supply-chain-security.md |
| https://jfrog.com/help/r/jfrog-security-user-guide/products/advanced-security | supply-chain-security.md |
| https://jfrog.com/help/r/jfrog-security-user-guide/products/runtime | supply-chain-security.md |
| https://jfrog.com/help/r/jfrog-security-user-guide/products/curation | supply-chain-security.md |
| https://jfrog.com/help/r/jfrog-rest-apis/apptrust-rest-apis | apptrust.md |
| https://github.com/jfrog/Evidence-Examples | release-lifecycle.md, ci-integration.md |

### General / cross-cutting

| URL | Notes |
|-----|-------|
| https://jfrog.com/help/home | JFrog Help Center landing |
| https://jfrog.com/help/r/jfrog-rest-apis | REST API index |

When you add a new documentation URL to any skill, add a row to the appropriate table above.
