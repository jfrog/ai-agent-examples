# JFrog AI Agent Examples

A curated collection of AI agent skills and rules for automating workflows on the JFrog Platform. Each example is a self-contained set of skills that an AI coding assistant can follow to accomplish domain-specific tasks through natural-language conversation.

---

**Disclaimer:** This repository is a collection of community examples and is **not** a formal JFrog product. These skills and rules are provided as-is for interacting with the JFrog Platform and its features. They are not officially supported, may not cover all edge cases, and should be reviewed before use in production environments.

---

## Overview

| Example | Suggested persona | Description |
|---------|-------------------|-------------|
| [**compliance-and-policies**](compliance-and-policies/) | Platform / security admins, release managers | Create lifecycle policies that validate evidence before promotion |
| [**platform-features**](platform-features/) | Developers, DevOps, platform engineers | 11 skills covering JFrog Platform APIs, CLI, security, and architecture patterns |
| [**onboarding-workflows**](onboarding-workflows/) | Platform admins, SRE, onboarding automation | Orchestrate multi-project onboarding with manifest-driven provisioning |

**Choosing an example:** Use **compliance-and-policies** for evidence-based promotion gates; **platform-features** for API/CLI reference and patterns; **onboarding-workflows** for provisioning projects, repos, members, and CI from a manifest.

## Repository structure

```
ai-agent-examples/
├── README.md                 # This file
├── .env.example             # Template for JFROG_URL, JFROG_ACCESS_TOKEN
├── global/                   # Shared rules applied across all examples
│   └── rules/
│       ├── interaction-questions.mdc
│       └── jfrog-platform.mdc
├── compliance-and-policies/  # Evidence-based lifecycle policies
│   ├── README.md
│   ├── rules/
│   └── skills/
├── platform-features/       # JFrog APIs, CLI, patterns (11 skills)
│   ├── README.md
│   ├── CONTRIBUTING.md
│   ├── rules/
│   └── skills/
└── onboarding-workflows/     # Manifest-driven project/repo onboarding
    ├── README.md
    ├── rules/
    ├── skills/
    ├── templates/
    └── scripts/
```

- **global/rules/** — Copy these into your IDE’s rules directory so they apply whenever you use any example.
- **&lt;example&gt;/skills/** and **&lt;example&gt;/rules/** — Copy the ones for the example(s) you use.

## Installation

Copy the skills and rules for the example(s) you want into your AI environment. Run commands from the **repository root** (the directory containing `global/`, `compliance-and-policies/`, etc.).

### Cursor

1. Copy **global** rules (recommended for all examples):
   ```bash
   mkdir -p .cursor/rules
   cp global/rules/*.mdc .cursor/rules/
   ```
2. Copy one or more examples:
   ```bash
   mkdir -p .cursor/skills
   # Example: compliance-and-policies
   cp -r compliance-and-policies/skills/* .cursor/skills/
   cp compliance-and-policies/rules/*.mdc .cursor/rules/ 2>/dev/null || true
   # Example: platform-features
   cp -r platform-features/skills/* .cursor/skills/
   cp platform-features/rules/*.mdc .cursor/rules/ 2>/dev/null || true
   # Example: onboarding-workflows
   cp -r onboarding-workflows/skills/* .cursor/skills/
   cp onboarding-workflows/rules/*.mdc .cursor/rules/ 2>/dev/null || true
   ```

### VS Code (GitHub Copilot)

- Copy skill folders into `.github/copilot/skills/` (or your Copilot skills path). Add rule content to `.github/copilot-instructions.md` or your project’s Copilot instructions so the agent follows JFrog conventions.

### Claude Code

- Copy skill folders into `.claude/skills/`. Put global and example rule content into `CLAUDE.md` or a dedicated rules file your environment reads.

### Windsurf

- Copy skills into `.windsurf/skills/` and rules into `.windsurf/rules/` (or the paths your Windsurf setup uses for skills and rules).

### JetBrains AI Assistant

- Paste skill instructions into AI Assistant custom instructions or project guidelines (e.g. `.junie/guidelines.md`). Include the contents of the relevant rule files so the assistant follows JFrog API and safety conventions.

### Other agents

- Skills use the open `SKILL.md` format. Copy the `skills/` directories into your agent’s skills location. See [agentskills.io](https://agentskills.io) for the broader ecosystem and tool support.

## Prerequisites

- A JFrog Platform instance (entitlements depend on the example: e.g. AppTrust for compliance-and-policies, Platform Admin for onboarding-workflows).
- Credentials: set `JFROG_URL` and `JFROG_ACCESS_TOKEN` (or use a `.env` file). Copy `.env.example` to `.env` and fill in your values. Keep `.env` out of version control.

```bash
cp .env.example .env
# Edit .env with your JFrog URL and access token
```

- Tools used by the examples: `curl`, `jq`; for onboarding-workflows also `yq`, Git.

## Using a skill

1. Install as above for your IDE.
2. Ask the agent in natural language, e.g.:
   - *"Create a promotion policy that requires SLSA provenance evidence"* (compliance-and-policies)
   - *"Set up a CI integration with security scans for my npm project"* (platform-features)
   - *"Onboard all projects from my-manifest.yaml"* (onboarding-workflows)

The agent will follow the skill’s workflow, use your credentials (from env or `.env`), and guide you step by step.

## Contributing

We welcome new examples and improvements to existing ones.

1. **New example:** Add a directory at the repo root with:
   - `README.md` — overview, who it’s for, prerequisites, usage.
   - `skills/` — at least one skill with `SKILL.md` (and optional `*-reference.md`, `assets/`).
   - `rules/` (optional) — example-specific `.mdc` rules.
2. **Existing example:** Follow the same layout; keep shared conventions in `global/rules/` and example-specific ones in that example’s `rules/`.
3. **Skills:** Include a clear desired state / success criteria and validation steps; use the standardized section order (Authentication, Prerequisites, Desired State, Workflow, Official Documentation, etc.) described in the plan.
4. **Overlapping domains:** If your skill touches Curation, AppTrust, Artifactory repos, or Access/projects, add a “Related skills” or “See also” reference to the other example(s) that cover the same end result.

## License

This project is licensed under the Apache License 2.0 — see the [NOTICE](NOTICE) file for details.
