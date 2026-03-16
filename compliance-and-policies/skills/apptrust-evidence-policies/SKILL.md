---
name: Apptrust Evidence Policies
description: Create JFrog project lifecycle policies that check for evidence existence on promotion or release events for applications with specific labels. Use when the user asks to create a policy, evidence policy, promotion policy, lifecycle policy, compliance check, or evidence validation for application promotions. Triggers on mentions of policy, evidence policy, promotion policy, lifecycle policy, compliance check, evidence validation, AppTrust promotion.
---

# Evidence Promotion Policy Creator

Create a JFrog lifecycle policy that validates evidence exists before allowing application promotion, scoped to applications with specific labels.

## Prerequisites

Follow [jfrog-apptrust-auth.md](jfrog-apptrust-auth.md) to authenticate with the JFrog Platform before proceeding.

## Desired State

After the workflow completes, the following must be true:

- A **template** exists (Rego policy) that evaluates evidence for the requested predicate type.
- A **rule** exists that binds the template to the predicate type (and any extra parameters).
- A **policy** exists, scoped to the chosen project or application, that blocks or warns on promotion when the evidence check fails.

Validate by fetching the created policy (and its rule/template) via the Unified Policy API and confirming scope, predicate type, and enforcement action match what the user requested.

## Workflow

Execute steps **in order**. Ask only **one question at a time**.
calls errors handling: If you get response "access denied: required entitlement not available" retry the call 3 times  

### Step 1: Validate Authentication

Follow [jfrog-apptrust-auth.md](jfrog-apptrust-auth.md) completely. Do not proceed until both authentication and AppTrust entitlement checks pass.

```bash
JFROG_URL=$(cat .jfrog/config | jq -r '.url')
JFROG_TOKEN=$(cat .jfrog/config | jq -r '.token')
```

### Step 2: Retrieve All Templates

```bash
TEMPLATES=$(curl -s -X GET \
  -H "Authorization: Bearer ${JFROG_TOKEN}" \
  -H "Content-Type: application/json" \
  "${JFROG_URL}/unifiedpolicy/api/v1/templates")
```

Store the full response for analysis in Step 5.

### Step 3: Retrieve All Rules

```bash
RULES=$(curl -s -X GET \
  -H "Authorization: Bearer ${JFROG_TOKEN}" \
  -H "Content-Type: application/json" \
  "${JFROG_URL}/unifiedpolicy/api/v1/rules")
```

Store the full response for analysis in Step 5.

### Step 4: Gather Evidence Requirements

Ask the user **one question at a time**:

**First — Predicate type:**

> What evidence predicate_type do you want to validate in your policy?
>
> Common predicate types:
> - `https://jfrog.com/evidence/build-signature/v1`
> - `https://jfrog.com/evidence/integration-test/v1`
> - `https://jfrog.com/evidence/approval/v1`
> - `https://jfrog.com/evidence/security-scan/v1`
> - `https://jfrog.com/evidence/cyclonedx/sbom/v1.6`
> - `https://sonarsource.com/evidence/sonarqube/v1`
> - `https://slsa.dev/provenance/v1`
> - Or provide a custom predicate_type
notice, these are not URLs, they are constant strings

**Second — Additional checks (ask after receiving predicate_type):**

> Do you want any additional evidence predicate checks beyond existence?
> For example: verifying specific field values, requiring multiple evidence types, etc.
> Say "no" if a simple existence check is sufficient.

### Step 5: Search for Existing Template or Rule

Analyze the data retrieved in Steps 2 and 3:

1. **Search templates for a direct match:**
   Examine each template's `rego` field for references to the user's requested predicate_type. A match means the template already handles this evidence type.

2. **If no template match — search rules:**
   If no template directly handles the predicate_type, check each rule's `parameters` for the predicate_type value. A matching rule means one already exists that feeds the predicate_type into a template.

3. **If a matching rule is found — get its template:**

   ```bash
   TEMPLATE=$(curl -s -X GET \
     -H "Authorization: Bearer ${JFROG_TOKEN}" \
     -H "Content-Type: application/json" \
     "${JFROG_URL}/unifiedpolicy/api/v1/templates/${TEMPLATE_ID}")
   ```

4. **Check for additional predicate checks:**
   If the user requested additional checks, examine the matched template's rego policy to verify it can handle them.

### Step 6: Present Findings

**Path A — Matching template/rule exists:**

Show the user the matching resources and suggest creating a policy using them:

> Found existing resources that handle your evidence requirements:
> - **Template**: `{template_name}` — {template_description}
> - **Rule**: `{rule_name}` — {rule_description} *(if applicable)*
>
> Would you like to create a policy using these?

Proceed to [Step 7](#step-7-gather-policy-configuration) if the user agrees.

**Path B — No match found:**

> No existing template handles the `{predicate_type}` evidence type.
> To create this policy, I'll need to create:
> 1. A new **template** (Rego policy for evidence checking)
> 2. A new **rule** (binding the template with parameters)
> 3. A new **policy** (applying on promotion for your labeled applications)
>
> Would you like to proceed?

Proceed to [Step 7](#step-7-gather-policy-configuration) if the user agrees.

### Step 7: Gather Policy Configuration

Ask one question at a time:

1. **Project key**: Which JFrog Project should contain this policy? *(required — policies must live in a JFrog Project unless the user explicitly opts out)*
2. **Policy scope**: should the policy scope be for project or application*
3. **Application labels**: If scope is project, which labels should the policy target? *(one or more)*
3. **Application keys**: If scope is application, which application keys should the policy target? *(one or more)*
4. **Resource names**: Suggest names following conventions or ask the user to provide them
5. **Action**: Which stage key should this policy gate and is it on entry, exit or release of that stage? *(one or more)*
### Step 8: Create Resources

Follow strict creation order: **template → rule → policy**.

Only create what is needed — skip template and rule if existing ones matched in Step 5.

#### Create Template (if no existing match)

```bash
curl -s -X POST \
  -H "Authorization: Bearer ${JFROG_TOKEN}" \
  -H "Content-Type: application/json" \
  "${JFROG_URL}/unifiedpolicy/api/v1/templates" \
  -d '{
    "name": "{template_name}",
    "description": "{template_description}",
    "category": "workflow",
    "parameters": [
      {
        "name": "predicate_type",
        "type": "string",
        "description": "evidence predicate type to validate"
      }
    ],
    "rego": "{rego_policy_checking_evidence_existence_and_additional_checks}",
    "scanners": [],
    "version": "1.0.0",
    "data_source_type": "evidence",
    "is_custom": true
  }'
```
The `rego` policy requires all new lines replaced by \n, tabs replaced by \t and " escaped as \"

The `rego` policy must check that evidence with the specified predicate_type exists. Include any additional predicate checks the user requested.

When patching a template, if a parameter was added, make sure all rules using this template_id are sending the new parameter

#### Create Rule (if no existing match)

```bash
curl -s -X POST \
  -H "Authorization: Bearer ${JFROG_TOKEN}" \
  -H "Content-Type: application/json" \
  "${JFROG_URL}/unifiedpolicy/api/v1/rules" \
  -d '{
    "name": "{rule_name}",
    "is_custom": true,
    "description": "{rule_description}",
    "template_id": "{template_id}",
    "parameters": {
      "predicate_type": "{user_predicate_type}"
    }
  }'
```

#### Create Policy

```bash
curl -s -X POST \
  -H "Authorization: Bearer ${JFROG_TOKEN}" \
  -H "Content-Type: application/json" \
  "${JFROG_URL}/unifiedpolicy/api/v1/policies" \
  -d '{
    "name": "{policy_name}",
    "description": "{policy_description}",
    "enabled": true,
    "rule_ids": ["{rule_id}"],
    "trigger": "promotion",
    "mode": "block",
    "action": { "type": "certify_to_gate", "stage": { "key": "{stage_key}", "gate":{entry_exit_or_release}" } },
    "scope": {
      "type": "{application_or_project}",
      "{application_keys_or_project_keys}": ["{appilcation_key_or_project_key}"],
      "labels": ["{label1}", "{label2}"]
    }
  }'
```

**Validate:** GET the created policy (and its rule/template) from the API and confirm scope, predicate type, and enforcement action match the user's request. Then confirm successful creation to the user and summarize what was created.

## Naming Conventions

| Field | Format |
|-------|--------|
| Name | 1-255 characters, must start with a letter |
| Description | 2048 characters characters, must start with a letter |

## Official Documentation

- [Templates API](https://jfrog.com/help/r/jfrog-rest-apis/templates)
- [Rules API](https://jfrog.com/help/r/jfrog-rest-apis/rules)
- [Lifecycle Policies API](https://jfrog.com/help/r/jfrog-rest-apis/lifecycle-policies)
- [JFrog AppTrust](https://jfrog.com/help/r/jfrog-security-documentation/jfrog-apptrust)
- [Evidence Management](https://jfrog.com/help/r/jfrog-artifactory-documentation/evidence-management)

## Related skills

For AppTrust entities (applications, versions, promotion) and Distribution release lifecycle, see **platform-features** (`jfrog-apptrust`, `jfrog-distribution`). For manifest-driven project onboarding, see **onboarding-workflows**.
