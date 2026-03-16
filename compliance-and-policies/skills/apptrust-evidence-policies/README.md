# Compliance and Policies

An Agent Skill that creates JFrog AppTrust lifecycle policies to validate evidence exists before allowing application version promotion through release stages. It leverages the JFrog Unified Policy API to build Rego-based compliance gates scoped to specific projects or applications.

## Who is this for?

**Suggested persona:** Platform and security admins, and release managers who need to enforce evidence-based promotion gates (e.g. SLSA provenance, security scans, quality gates) before applications can be promoted.

## What It Does

When you ask the agent to create a promotion policy, it will:

1. Authenticate with your JFrog Platform (via access token)
2. Check for existing templates and rules that already handle the requested evidence type and content checks
3. Gather your requirements interactively (predicate type, scope, target stage)
4. Create the necessary resources in order: **template** (Rego policy) -> **rule** (parameterized binding) -> **policy** (scoped enforcement)

The result is a lifecycle policy that **blocks or warns on promotion** unless the required evidence is attached to the application version or its releasables.

## Prerequisites

- A JFrog Platform instance with **AppTrust** entitlement
- An access token with policy management privileges
- `curl` and `jq` installed locally

## Supported Evidence Types

The skill can create policies for any predicate type, including:

| Predicate Type | Description |
|---|---|
| `https://jfrog.com/evidence/build-signature/v1` | Build signature verification |
| `https://jfrog.com/evidence/integration-test/v1` | Integration test results |
| `https://jfrog.com/evidence/approval/v1` | Manual or automated approval |
| `https://jfrog.com/evidence/security-scan/v1` | Security scan results |
| `https://jfrog.com/evidence/cyclonedx/sbom/v1.6` | CycloneDX SBOM |
| `https://sonarsource.com/evidence/sonarqube/v1` | SonarQube quality gate |
| `https://slsa.dev/provenance/v1` | SLSA provenance |

Custom predicate types are also supported and it is advised to add your custom evidence schema under assets for improving the skill content handling.

## Usage

Ask the agent to create a policy using natural language:

- *"Create a promotion policy that requires SLSA provenance evidence"*
- *"Set up an evidence compliance check for SonarQube quality gates on my app"*
- *"Add a lifecycle policy requiring build signatures before releasing to production"*

The agent will walk you through each configuration choice one question at a time.

## Policy Scope Options

Policies can be scoped to:

- **Project** -- applies to all applications within a JFrog Project that match specified labels
- **Application** -- applies to specific application keys

## How the Rego Policy Works

Templates contain [Rego](https://www.openpolicyagent.org/docs/latest/policy-language/) policies that evaluate evidence attached to a release. The policy engine receives an `input` object containing:

- `input.params` -- parameters passed from the rule (e.g., the predicate type to check)
- `input.data` -- the release data including evidence from all layers (release, artifact, build)

A simple existence check collects evidence from all layers and verifies at least one entry matches the requested predicate type. More advanced checks can inspect specific fields within the evidence predicate (e.g., SLSA builder ID, runner environment, source repository).

## Example Assets

The `assets/` directory contains reference files:

| File | Description |
|---|---|
| `example_rego_simple_type_check.rego` | Rego policy that checks evidence exists by predicate type |
| `example_rego_slsa_type_check.rego` | Rego policy that validates SLSA provenance with builder and repo checks |
| `example_rego_input.json` | Sample input object the Rego policy evaluates against |
| `example_slsa_evidence.json` | Sample SLSA provenance evidence payload |
| `example_sonar_evidence.json` | Sample SonarQube quality gate evidence payload |

## API Reference

| Resource | Endpoint | Docs |
|---|---|---|
| Templates | `/unifiedpolicy/api/v1/templates` | [Templates API](https://jfrog.com/help/r/jfrog-rest-apis/templates) |
| Rules | `/unifiedpolicy/api/v1/rules` | [Rules API](https://jfrog.com/help/r/jfrog-rest-apis/rules) |
| Policies | `/unifiedpolicy/api/v1/policies` | [Policies API](https://jfrog.com/help/r/jfrog-rest-apis/lifecycle-policies) |

## Naming Conventions

All resource names and descriptions must follow these formats:

- **Name**: 1-255 characters, must start with a letter
- **Description**: 2048 characters characters
