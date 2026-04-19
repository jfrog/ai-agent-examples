# Contributing to JFrog Agent Skills

This document describes skill conventions, how to update skills, and the full catalog of public data sources used to build and maintain them.

## Skill conventions

### Directory layout

- Each skill lives in a folder `skills/jfrog-<product>/`.
- **Required:** `SKILL.md` — main instructions, auth, and high-level flow.
- **Optional:** `*-reference.md` — API endpoints, command syntax, or detailed reference material. Keep long catalogs in reference files so the main skill stays scannable.

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

### Style rules

- **Authentication:** Put an "Authentication" section at the top of each `SKILL.md` that includes:
  - **Primary:** JFrog CLI **2.100.0+**, `jf config`, and **`jf api <path>`** per `skills/jfrog-cli/jf-api-patterns.md` (credentials from config; no bearer header in happy path).
  - **Fallback:** the `Authorization: Bearer $JFROG_ACCESS_TOKEN` header for `curl` when the CLI is missing or below 2.100.0.
  - Auth per `skills/jfrog-cli/login-flow.md`: (1) resolve the active environment from `jf config show`, (2) **show URLs and ask the user to confirm** the target platform, (3) **`jf api /artifactory/api/v1/system/readiness`** after confirmation, (4) agent-driven web login that saves credentials via `jf config add` if needed.
- **Pre-flight check:** For skills that depend on a service other than Artifactory (Xray, Curation, AppTrust, Lifecycle/Distribution), add a `> **Pre-flight:**` callout immediately after the Authentication section. This must instruct the agent to ping the service and stop early if unavailable. See `skills/jfrog-cli/preflight.md` for the canonical list of ping endpoints.
- **Parallelization:** For skills whose operations can be batched (creating multiple repos, users, or packages), add a "Parallelization" section noting which calls are independent and can run concurrently.
- **API examples:** Prefer **`jf api /...`** with path-only URLs. For **`curl` fallback**, use `$JFROG_URL` in URL patterns (e.g. `https://$JFROG_URL/artifactory/api/...`). Do not hardcode specific JFrog hostnames.
- **Official Documentation:** End each `SKILL.md` with an "Official Documentation" (or "Documentation") section listing 2–5 links to the relevant JFrog Help / REST API / CLI docs.
- **Reference files:** Name API/command catalogs and detailed references as `*-reference.md` (e.g. `rest-api-reference.md`, `aql-reference.md`, `events-reference.md`).

## Security

Every skill interacts with authenticated JFrog Platform APIs. These rules apply to all skill content — `SKILL.md` files, reference files, and `login-flow.md`.

### Credential handling

- **Never print tokens.** Skill instructions must never `echo`, `cat`, or otherwise display access tokens, refresh tokens, or API keys in terminal output. Extract tokens silently into shell variables.
- **Never surface tokens in chat.** The agent must not repeat token values back to the user. When confirming auth, use phrases like "authenticated successfully" or "token is set" — never the token itself.
- **Never hardcode tokens.** Use `$JFROG_ACCESS_TOKEN` in all examples. Never include real or example JWT strings that could be confused with live credentials.

### Shell safety

- **Quote all variables** in shell commands (`"${VAR}"`, not `$VAR`).
- **Avoid shell interpolation for secrets.** When passing tokens or user-controlled values to Python/Node scripts, use environment variables (`os.environ["VAR"]`) or stdin — never inline `${VAR}` inside heredoc code. Use quoted heredocs (`<< 'EOF'`) to prevent shell expansion inside script bodies.
- **Validate URLs before use.** Always ping the server (`/artifactory/api/system/ping`) before using a user-provided URL in further API calls. Do not pass unvalidated input to `curl` or other network commands.

### Credential storage

- **`jf config` is the sole credential store.** All tokens are stored via `jf config add` (encrypted at rest). Never store tokens in plaintext files, environment variable profiles, or project directories.
- **Never store credentials in project files.** Tokens, URLs with embedded credentials, and auth configs must never be written to the workspace or committed to version control.

### Transient session variables

- Token and URL values may be extracted from `jf config` into shell variables for the current session (e.g. for **`curl` fallback** or manifest URL checks). Routine calls should use **`jf api`**. These variables are transient and must never be persisted, exported to profiles, or logged.
- **`JFROG_ACCESS_TOKEN` is sensitive.** Never use it in `echo`, logging, or debug output.
- **`JFROG_URL` is non-sensitive** and can be displayed freely.

### Review checklist for contributors

When adding or modifying a skill, verify:

1. No `echo`, `cat`, or `print()` of token values anywhere in the instructions.
2. All shell scripts use quoted variables and quoted heredocs for embedded scripts.
3. Credentials are stored only via `jf config` -- no plaintext files or env var profiles.
4. No real tokens, passwords, or hostnames appear in examples.
5. Platform URL confirmation and **`jf api /artifactory/api/v1/system/readiness`** (or ping) precede other authenticated API work on a server.
6. Skills for non-Artifactory services include a pre-flight ping check (see `skills/jfrog-cli/preflight.md`).

### Reference file naming

- `rest-api-reference.md`, `api-reference.md` — REST API endpoint summaries; prefer **`jf api`** examples with **`curl`** as fallback where applicable.
- `*-reference.md` — other product-specific references (AQL, package types, events, CLI command groups).

## How to update a skill

1. **Identify the data source**  
   Use the [Data source catalog](#data-source-catalog) below to find the official doc URL(s) for the skill you’re editing.

2. **Refresh from the source**  
   Open the linked JFrog Help / API / CLI page and note new endpoints, parameters, or behavior.

3. **Update reference files first**  
   If the change is in API or command details, update the appropriate `*-reference.md` (e.g. add a new endpoint or command with method, path, and a minimal example).

4. **Update SKILL.md if needed**  
   If new capabilities change high-level flow or triggers, add a short subsection or bullet in `SKILL.md` and ensure the "Official Documentation" links still match.

5. **Update this catalog when adding sources**  
   If you pull from a new doc URL, add it to the relevant skill’s section in [Data source catalog](#data-source-catalog) with the target file(s).

6. **Test**  
   Ask your AI agent something that should trigger the skill (e.g. “How do I create a Docker remote repo in Artifactory?”) and confirm the answer aligns with the updated content.

---

## Data source catalog

Below are the public documentation and source URLs used to create and maintain each skill. Use this list to update skills when JFrog docs or APIs change.

### jfrog-artifactory

| URL | Feeds into |
|-----|------------|
| https://docs.jfrog.com/integrations/docs/jfrog-api | rest-api-reference.md |
| https://docs.jfrog.com/artifactory/docs/repository-management | SKILL.md, rest-api-reference.md |
| https://docs.jfrog.com/artifactory/docs/federated-repositories | SKILL.md |
| https://docs.jfrog.com/artifactory/docs/artifactory-query-language | aql-reference.md |
| Package-type registry URLs (Docker, Maven, npm, PyPI, Go, Helm, NuGet, Terraform, Cargo, Conan, Pub, etc.) | package-types-reference.md |

### jfrog-security

| URL | Feeds into |
|-----|------------|
| https://docs.jfrog.com/security/reference/about-security-apis | xray-api-reference.md |
| https://docs.jfrog.com/security/docs/xray | SKILL.md, scanning-guide.md |
| https://docs.jfrog.com/security/docs/advanced-security | SKILL.md |
| https://docs.jfrog.com/security/docs/runtime | SKILL.md |
| https://docs.jfrog.com/security/docs/apis | SKILL.md |

### jfrog-access

| URL | Feeds into |
|-----|------------|
| https://jfrog.com/help/r/jfrog-rest-apis/access-tokens | api-reference.md |
| https://docs.jfrog.com/administration/reference/getPermissions | api-reference.md |
| https://docs.jfrog.com/projects/docs/projects| SKILL.md |
| https://docs.jfrog.com/administration/docs/access-federation | SKILL.md |
| https://docs.jfrog.com/administration/reference/getProjectEnvironments | SKILL.md |

### jfrog-distribution

| URL | Feeds into |
|-----|------------|
| https://jfrog.com/help/r/jfrog-rest-apis/distribution-rest-apis | api-reference.md |
| https://docs.jfrog.com/governance/docs/release-lifecycle-management | SKILL.md, api-reference.md |
| https://docs.jfrog.com/governance/docs/evidence-management | SKILL.md |
| https://docs.jfrog.com/governance/docs/create-evidence-using-rest-apis | SKILL.md |
| https://docs.jfrog.com/governance/reference/prepareevidence | SKILL.md |
| https://github.com/jfrog/Evidence-Examples | SKILL.md, api-reference.md |

### jfrog-apptrust

| URL | Feeds into |
|-----|------------|
| https://jfrog.com/help/r/jfrog-rest-apis/apptrust-rest-apis | SKILL.md, api-reference.md |
| https://jfrog.com/help/r/jfrog-security-documentation/jfrog-apptrust | SKILL.md |

### jfrog-curation

| URL | Feeds into |
|-----|------------|
| https://docs.jfrog.com/security/docs/curation-intro | SKILL.md |
| https://jfrog.com/curation | SKILL.md |

### jfrog-mission-control

| URL | Feeds into |
|-----|------------|
| https://jfrog.com/help/r/jfrog-rest-apis/mission-control | SKILL.md, api-reference.md |
| https://jfrog.com/help/r/jfrog-platform-administration-documentation/mission-control | SKILL.md |

### jfrog-runtime

| URL | Feeds into |
|-----|------------|
| https://docs.jfrog.com/security/docs/runtime | SKILL.md |
| https://docs.jfrog.com/security/docs/apis | SKILL.md, api-reference.md |

### jfrog-workers

| URL | Feeds into |
|-----|------------|
| https://docs.jfrog.com/administration/docs/workers-overview | SKILL.md |
| https://docs.jfrog.com/administration/docs/typescript-code-for-workers| SKILL.md |
| https://docs.jfrog.com/administration/reference/createWorker | SKILL.md, api-reference.md |
| https://docs.jfrog.com/administration/docs/configure-workers-for-custom-flows | events-reference.md |

### jfrog-cli

| URL | Feeds into |
|-----|------------|
| https://docs.jfrog.com/integrations/docs/download-and-install-the-jfrog-cli | SKILL.md, login-flow.md |
| https://docs.jfrog.com/integrations/docs/jfrog-cli | SKILL.md |
| https://jfrog.com/help/r/jfrog-cli | SKILL.md |
| https://jfrog.com/help/r/jfrog-cli/cli-for-jfrog-artifactory | artifactory-commands.md |
| https://docs.jfrog.com/artifactory/docs/binaries-management-with-jfrog-artifactory | artifactory-commands.md |
| https://jfrog.com/help/r/jfrog-cli/cli-for-jfrog-security | security-commands.md |
| https://github.com/jfrog/documentation/blob/main/SUMMARY.md | platform-commands.md |
| https://github.com/jfrog/jfrog-cli (login flow reverse-engineered from source) | login-flow.md |
| Internal -- service ping endpoints collected from product API references | preflight.md |
| Internal -- `jf api` usage patterns | jf-api-patterns.md |

### jfrog-patterns

| URL or source | Feeds into |
|---------------|------------|
| https://docs.jfrog.com/integrations/docs/build-integration| ci-integration.md |
| https://docs.jfrog.com/artifactory/docs/repository-management | repositories.md |
| https://docs.jfrog.com/governance/docs/release-lifecycle-management| release-lifecycle.md |
| https://docs.jfrog.com/governance/docs/evidence-management | release-lifecycle.md, ci-integration.md |
| https://docs.jfrog.com/security/docs/xray | supply-chain-security.md |
| https://docs.jfrog.com/security/docs/advanced-security | supply-chain-security.md |
| https://docs.jfrog.com/security/docs/runtime | supply-chain-security.md |
| https://docs.jfrog.com/security/docs/curation-intro | supply-chain-security.md |
| https://jfrog.com/help/r/jfrog-rest-apis/apptrust-rest-apis | apptrust.md |
| https://github.com/jfrog/Evidence-Examples | release-lifecycle.md, ci-integration.md |
| Application source extraction (`.cursor/plans/extract_patterns_&_getstarted_info_b018056f.plan.md`) | All pattern files, journeys.md, SKILL.md |
| Internal -- action-to-flow mapping for agent behavior | flow-suggestions.md |

### General / cross-cutting

| URL | Notes |
|-----|--------|
| https://jfrog.com/help/home | JFrog Help Center landing |
| https://docs.jfrog.com/integrations/docs/jfrog-api | REST API index |

When you add a new documentation URL to any skill, add a row to the appropriate table above (and to the general section if it applies to multiple skills).

---

## Installation

Skills are installed via the [`skills`](https://npmjs.com/package/skills) CLI, which installs directly from this git repo:

```bash
npx skills add git@github.jfrog.info:evgenid/jfrog-skills.git --skill '*'
```

The `skills` CLI discovers all `SKILL.md` files under the `skills/` directory automatically. It supports 37+ agents, symlink/copy modes, global/project scope, and updates. See the [README](README.md#installation) for full usage.
