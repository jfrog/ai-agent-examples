---
name: detect-existing-patterns
description: Detect existing project and repository naming patterns on the JFrog Platform before onboarding. Queries all projects and repos, analyzes naming conventions, and presents the user with a choice between following detected patterns or using the standard naming rules. Use before creating new projects or repositories.
---

# Detect Existing Naming Patterns

Queries the JFrog Platform for existing projects and repositories, analyzes their naming conventions, and presents the user with a choice between the detected pattern and the standard onboarding pattern.

## API transport

Prefer **`jf api`** per [../../../platform-features/skills/jfrog-cli/jf-api-patterns.md](../../../platform-features/skills/jfrog-cli/jf-api-patterns.md) after `jf config` and platform confirmation. Examples below use **`curl`** as fallback.

## Inputs

- `JFROG_URL` -- Platform base URL (for `curl` fallback; derive from `jf config show` when using CLI)
- `JFROG_ACCESS_TOKEN` -- Admin token (for `curl` fallback only)
- `new_project_key` -- the project key about to be onboarded (used to generate examples)
- `new_ecosystems` -- list of ecosystems for the new project (used to generate examples)
- `state_project_key` -- (optional) the state/system project key to exclude from analysis (default: `system`)

## Output

A `naming_pattern` object with these fields (passed to `jfrog-create-repos`):

| Field | Type | Description | Default (standard) |
|-------|------|-------------|-------------------|
| `separator` | string | Character between name components | `-` |
| `virtual_suffix` | string | Type label for virtual repos; empty string means no suffix | `""` (no suffix) |
| `type_map` | object | Maps logical types to their name tokens | `{"local": "local", "remote": "remote"}` |
| `eco_map` | object | Maps manifest ecosystem names to repo name tokens (only entries that differ from the identity mapping) | `{"pip": "pypi"}` |

The standard (default) pattern produces names like `{key}-npm-local`, `{key}-npm-remote`, `{key}-npm`.

## When to Skip

- If the platform has **no existing projects** (or only the state project), skip detection entirely and use the standard pattern. Do not ask the user anything.
- If no repos can be found across existing projects, skip detection and use the standard pattern.

## Workflow

### 0. Load credentials

```bash
if [ -z "$JFROG_URL" ] || [ -z "$JFROG_ACCESS_TOKEN" ]; then
  if [ -f .env ]; then
    set -a; source .env; set +a
  fi
fi
```

### 1. Fetch all existing projects

Run with `required_permissions: ["full_network"]`.

```bash
BODY=/tmp/all-projects.json
CODE=/tmp/all-projects.code
jf api /access/api/v1/projects >"$BODY" 2>"$CODE"
HTTP_CODE=$(tr -d '\r\n' < "$CODE")

if [ "$HTTP_CODE" = "200" ]; then
  PROJECT_KEYS=$(jq -r '.[].project_key' "$BODY")
else
  echo "WARN: Could not list projects (HTTP $HTTP_CODE). Skipping pattern detection."
  # Use standard pattern
fi
```

**Fallback:** `curl -s -o /tmp/all-projects.json -w "%{http_code}" -H "Authorization: Bearer $JFROG_ACCESS_TOKEN" "$JFROG_URL/access/api/v1/projects"`

Filter out the state project (default key `system`, or the value of `state_project_key` input):

```bash
PROJECT_KEYS=$(echo "$PROJECT_KEYS" | grep -v "^${STATE_PROJECT_KEY}$")
```

If `PROJECT_KEYS` is empty after filtering, skip detection -- use the standard pattern and exit this skill.

### 2. Fetch repositories per project

Run with `required_permissions: ["full_network"]`. Collect all repo keys grouped by project. Add `sleep 1` between iterations to avoid rate limiting.

```bash
ALL_REPOS=""
for PROJ in $PROJECT_KEYS; do
  RB=/tmp/repos-${PROJ}.json
  RC=/tmp/repos-${PROJ}.code
  jf api "/artifactory/api/repositories?project=${PROJ}" >"$RB" 2>"$RC"
  HTTP_CODE=$(tr -d '\r\n' < "$RC")

  if [ "$HTTP_CODE" = "200" ]; then
    REPO_KEYS=$(jq -r '.[].key' "$RB")
    for RK in $REPO_KEYS; do
      ALL_REPOS="${ALL_REPOS}${PROJ}|${RK}\n"
    done
  fi
  sleep 1
done
```

If no repos were collected, skip detection -- use the standard pattern and exit this skill.

### 3. Analyze naming patterns

For each project's repos, decompose repo names to detect the naming convention. The analysis checks three characteristics: **separator**, **component order**, and **virtual suffix**.

#### Known tokens for matching

- **Ecosystem tokens**: `npm`, `maven`, `pypi`, `go`, `docker`, `helm`, `nuget`, `generic`, `gradle`, `cargo`, `conan`, `conda`, `gems`, `gitlfs`, `bower`, `cocoapods`, `pub`, `python`, `pip`
- **Type tokens**: `local`, `remote`, `virtual`
- **Type abbreviations**: `loc` -> `local`, `rem` -> `remote`, `virt` -> `virtual`

#### Detection algorithm

For each `PROJECT_KEY | REPO_KEY` pair:

1. **Strip the project key** from the repo name (it may appear as a prefix or elsewhere). Record the position where it appears.

2. **Identify the separator**. Try each candidate separator (`-`, `_`, `.`) and split the repo name. The separator that produces segments matching the most known tokens (project key, ecosystem, type) wins. If all three produce equal matches, default to `-`.

3. **Split the repo name** using the winning separator.

4. **Classify each segment** as one of:
   - `project_key` -- matches the project key
   - `ecosystem` -- matches a known ecosystem token
   - `type` -- matches a known type token or abbreviation
   - `unknown` -- does not match any known token

5. **Record the component order** -- the sequence of classified segments. For example: `["project_key", "ecosystem", "type"]` or `["ecosystem", "project_key", "type"]`.

6. **Record the type mapping** -- what string was used for each logical type. For example, if `loc` was used instead of `local`, record `{"local": "loc"}`.

7. **Record the ecosystem mapping** -- what string was used. For example, if `python` was used instead of `pypi`, record `{"pip": "python"}`.

8. **Determine the virtual suffix**. Look at repos with `rclass: virtual` (from the repo list API response which includes `type` field). Compare their names to corresponding local/remote repos:
   - If the virtual repo name has **no type segment** (e.g., `myproj-npm`): `virtual_suffix` = `""` (empty)
   - If it has an explicit type segment (e.g., `myproj-npm-virtual`): `virtual_suffix` = that segment

#### Aggregation across repos

After analyzing all repos:

1. **Count separator usage** -- pick the separator with the highest frequency.
2. **Count component order** -- pick the order with the highest frequency.
3. **Count virtual suffix** -- pick the suffix with the highest frequency.
4. **Build the type_map and eco_map** from the most common mappings.
5. **Compute confidence**:
   - **High**: 80%+ of repos match the same pattern
   - **Medium**: 50-79% match the most common pattern
   - **Low**: less than 50% match any single pattern

### 4. Present options to the user

Use the `AskQuestion` tool to present the choice. Before asking, display context about what was found.

#### Generate example names

Using the user's `new_project_key` and `new_ecosystems`, generate concrete example repo names for both options.

**Detected pattern example** -- apply the detected `separator`, `order`, `virtual_suffix`, `type_map`, and `eco_map`:

```
# If detected pattern is: {project_key}_{ecosystem}_{type}, virtual_suffix="virtual"
# For project "webapp", ecosystem "npm":
#   webapp_npm_local
#   webapp_npm_remote
#   webapp_npm_virtual
```

**Standard pattern example** -- always `{key}-{ecosystem}-{type}`, no virtual suffix, `pip`->`pypi`:

```
# For project "webapp", ecosystem "npm":
#   webapp-npm-local
#   webapp-npm-remote
#   webapp-npm
```

#### Present the choice

Display a summary message to the user:

```
Found {N} existing projects with {M} repositories on the platform.

Detected naming pattern (confidence: {high/medium/low}):
  Separator: "{sep}"
  Order: {project_key}{sep}{ecosystem}{sep}{type}
  Virtual repos: {description of virtual suffix}
  {Any notable ecosystem mappings, e.g. "pip ecosystem uses 'python' in repo names"}

Existing examples:
  {list 3-5 actual existing repo names as examples}

Examples for your new project "{new_project_key}" with ecosystems [{new_ecosystems}]:

  Option A -- Follow existing pattern:
    {generated detected-pattern examples, one line per repo}

  Option B -- Standard pattern:
    {generated standard-pattern examples, one line per repo}
```

Then use `AskQuestion`:

```
AskQuestion:
  id: naming_pattern_choice
  prompt: "Which naming pattern would you like to use for the new repositories?"
  options:
    - id: detected
      label: "Option A -- Follow existing pattern ({detected_pattern_summary})"
    - id: standard
      label: "Option B -- Standard pattern ({key}-{ecosystem}-{type})"
```

#### Detected pattern matches standard

If the detected pattern is identical to the standard pattern (separator = `-`, order = `[project_key, ecosystem, type]`, virtual_suffix = `""`, eco_map = `{"pip": "pypi"}`), do **not** ask the user. Simply report:

```
Existing repositories already follow the standard naming pattern. Proceeding with standard naming.
```

And return the standard naming_pattern.

### 5. Return the naming_pattern

Based on the user's choice (or the default when detection is skipped or the patterns match), return the `naming_pattern` object:

**Standard pattern** (default):
```yaml
separator: "-"
virtual_suffix: ""
type_map:
  local: "local"
  remote: "remote"
eco_map:
  pip: "pypi"
```

**Detected pattern** (example):
```yaml
separator: "_"
virtual_suffix: "virtual"
type_map:
  local: "local"
  remote: "remote"
eco_map:
  pip: "python"
```

The orchestration skill stores this and passes it to `jfrog-create-repos` for each project.

## Repo Name Generation

Given a `naming_pattern`, generate a repo key as follows:

```bash
SEP="${NAMING_SEPARATOR:--}"

# Map ecosystem name to repo token
ECO_TOKEN="$ECOSYSTEM"
# Apply eco_map overrides (e.g., pip -> pypi)
case "$ECOSYSTEM" in
  pip) ECO_TOKEN="${ECO_MAP_PIP:-pypi}" ;;
esac

# Local repo
LOCAL_TYPE="${TYPE_MAP_LOCAL:-local}"
REPO_KEY="${PROJECT_KEY}${SEP}${ECO_TOKEN}${SEP}${LOCAL_TYPE}"

# Remote repo
REMOTE_TYPE="${TYPE_MAP_REMOTE:-remote}"
REPO_KEY="${PROJECT_KEY}${SEP}${ECO_TOKEN}${SEP}${REMOTE_TYPE}"

# Virtual repo
VIRTUAL_SUFFIX="${NAMING_VIRTUAL_SUFFIX:-}"
if [ -z "$VIRTUAL_SUFFIX" ]; then
  REPO_KEY="${PROJECT_KEY}${SEP}${ECO_TOKEN}"
else
  REPO_KEY="${PROJECT_KEY}${SEP}${ECO_TOKEN}${SEP}${VIRTUAL_SUFFIX}"
fi
```

## Error Handling

- If the projects API fails, log a warning and fall back to the standard pattern. Do not abort onboarding.
- If the repos API fails for a specific project, skip that project's repos in the analysis and continue.
- If the detected pattern has **low confidence**, include a note in the presentation: "The detected pattern has low confidence because existing repos use mixed naming conventions."
- Pattern detection is best-effort; it must never block or abort the onboarding workflow.
