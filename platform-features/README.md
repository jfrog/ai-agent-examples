# Platform Features

Agent skills that give your AI assistant deep knowledge of the JFrog Platform — REST APIs, OneModel GraphQL, CLI, and architectural patterns. Use these when you need to work with Artifactory, Xray, Access, Distribution, Curation, AppTrust, and related products from natural language.

## Who is this for?

**Suggested persona:** Developers, DevOps engineers, and platform engineers who use the JFrog Platform day-to-day. Use this example when you need API reference, CLI usage, or architecture patterns rather than a full onboarding or policy workflow.

## What's in this example

Skills are in the open `SKILL.md` format. Each skill folder under `skills/` contains a main `SKILL.md` and optional `*-reference.md` files with API or command catalogs.

**Examples of what you can ask:**

- "Set up a CI integration with security scans for my npm project"
- "Create a basic repository setup with local, remote, and virtual repos"
- "Check if the npm package lodash@4.17.20 has any critical vulnerabilities"
- "Promote my release bundle to production with security gates"
- "Help me pick the right JFrog architecture pattern for my team"
- "Run a GraphQL query against OneModel to list my applications"

## Available skills

| Skill | Triggers when you mention... |
|-------|------------------------------|
| **jfrog-artifactory** | artifactory, repository, artifact, deploy, docker registry, build info, AQL, replication, federation |
| **jfrog-security** | xray, vulnerability, CVE, scan, policy, watch, violation, SBOM, SAST, secrets detection |
| **jfrog-access** | access token, permission, user, group, project, authentication, RBAC |
| **jfrog-distribution** | distribution, release bundle, promote, environment, edge node, release lifecycle, evidence |
| **jfrog-curation** | curation, package firewall, blocked package, curated repository, waiver, supply chain |
| **jfrog-apptrust** | apptrust, application entity, application version, trusted release, promote version, rollback |
| **jfrog-runtime** | runtime, runtime cluster, running images, runtime sensor, container monitoring, node health |
| **jfrog-mission-control** | mission control, JPD, platform deployment, license, proxy, deployment health |
| **jfrog-workers** | worker, serverless, event hook, TypeScript worker, BEFORE_DOWNLOAD, custom logic |
| **jfrog-cli** | jf command, jfrog cli, jf rt, jf audit, jf scan, jf docker, file spec |
| **jfrog-onemodel** | onemodel, graphql, unified API, applications, evidence, packages, catalog, and more |
| **jfrog-patterns** | pattern, best practice, architecture, get started, CI integration, multi-site, AppTrust |

## Prerequisites

- JFrog Platform access (Artifactory, Xray, Access, etc.)
- JFrog CLI (`jf`) for authentication, or `JFROG_URL` and `JFROG_ACCESS_TOKEN` (see repo root `.env.example`)

## Installation

Copy the skills and rules into your AI environment. From the **repository root** (parent of `platform-features/`):

- **Cursor:** Copy `platform-features/skills/*` into `.cursor/skills/` and `platform-features/rules/*` into `.cursor/rules/`. Also copy `global/rules/*` into `.cursor/rules/`.
- **Other IDEs:** See the main [README](../README.md) for installation instructions per IDE.

## Structure

```
platform-features/
├── README.md           # This file
├── CONTRIBUTING.md     # Conventions and data-source catalog
├── rules/
│   └── contributing.mdc
└── skills/
    ├── jfrog-artifactory/
    ├── jfrog-security/
    ├── jfrog-access/
    ├── jfrog-distribution/
    ├── jfrog-curation/
    ├── jfrog-apptrust/
    ├── jfrog-runtime/
    ├── jfrog-mission-control/
    ├── jfrog-workers/
    ├── jfrog-cli/
    ├── jfrog-onemodel/
    └── jfrog-patterns/
```

## Data sources

Skills are derived from public JFrog documentation and REST APIs. See [CONTRIBUTING.md](CONTRIBUTING.md#data-source-catalog) for the full catalog.

- [JFrog Help Center](https://jfrog.com/help/home)
- [JFrog REST APIs](https://jfrog.com/help/r/jfrog-rest-apis)
- [JFrog CLI Documentation](https://docs.jfrog.com/integrations/docs/jfrog-cli)
- [Evidence Examples (GitHub)](https://github.com/jfrog/Evidence-Examples)

## Related examples

- **compliance-and-policies** — Create evidence-based lifecycle policies (uses AppTrust/Distribution concepts).
- **onboarding-workflows** — Manifest-driven project/repo onboarding; includes workflows that use Artifactory, Access, and Curation.
