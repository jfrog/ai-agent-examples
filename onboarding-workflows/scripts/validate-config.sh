#!/usr/bin/env bash
# validate-config.sh -- Validate an onboarding manifest YAML file
# Usage: ./scripts/validate-config.sh [path-to-manifest.yaml]
#
# Checks:
# - File exists and is readable
# - Required fields are present
# - Project keys follow naming rules
# - Ecosystems are valid values
# - GitHub repos are in owner/repo format (supports multiple repos per project)

set -euo pipefail

MANIFEST="${1:-templates/manifest-template.yaml}"
VALID_ECOSYSTEMS="npm maven pip go docker helm"
ERRORS=0

echo "Validating manifest: $MANIFEST"
echo "================================"

# Check file exists
if [ ! -f "$MANIFEST" ]; then
  echo "ERROR: Manifest file not found: $MANIFEST"
  exit 1
fi

# Check required tools
if ! command -v yq &>/dev/null; then
  echo "WARNING: 'yq' not installed. Install with: brew install yq"
  echo "Falling back to basic grep-based validation..."

  # Basic validation without yq
  if ! grep -q "^jfrog:" "$MANIFEST"; then
    echo "ERROR: Missing 'jfrog' section"
    ERRORS=$((ERRORS + 1))
  fi

  if ! grep -q "^jfrog_projects:" "$MANIFEST"; then
    echo "ERROR: Missing 'jfrog_projects' section"
    ERRORS=$((ERRORS + 1))
  fi

  if ! grep -q "project_key:" "$MANIFEST"; then
    echo "ERROR: No projects defined (missing project_key)"
    ERRORS=$((ERRORS + 1))
  fi

  if [ "$ERRORS" -gt 0 ]; then
    echo ""
    echo "FAILED: $ERRORS error(s) found (basic validation only)"
    exit 1
  else
    echo "PASSED: Basic validation (install yq for full validation)"
    exit 0
  fi
fi

# Full validation with yq
echo ""

# Check jfrog.url
JFROG_URL=$(yq '.jfrog.url // ""' "$MANIFEST")
if [ -z "$JFROG_URL" ] || [ "$JFROG_URL" = "null" ]; then
  echo "ERROR: jfrog.url is not set"
  ERRORS=$((ERRORS + 1))
else
  echo "OK: jfrog.url = $JFROG_URL"
fi

# Check github.oidc_setup (must be true or false if present)
OIDC_SETUP=$(yq '.github.oidc_setup // ""' "$MANIFEST")
if [ -z "$OIDC_SETUP" ] || [ "$OIDC_SETUP" = "null" ]; then
  echo "WARNING: github.oidc_setup is not set (defaults to false -- secrets-based auth)"
elif [ "$OIDC_SETUP" = "true" ] || [ "$OIDC_SETUP" = "false" ]; then
  echo "OK: github.oidc_setup = $OIDC_SETUP"
else
  echo "ERROR: github.oidc_setup must be true or false, got '$OIDC_SETUP'"
  ERRORS=$((ERRORS + 1))
fi

# Check projects array
PROJECT_COUNT=$(yq '.jfrog_projects | length' "$MANIFEST")
if [ "$PROJECT_COUNT" -eq 0 ]; then
  echo "ERROR: No projects defined"
  ERRORS=$((ERRORS + 1))
else
  echo "OK: $PROJECT_COUNT project(s) defined"
fi

# Validate each project
for i in $(seq 0 $((PROJECT_COUNT - 1))); do
  echo ""
  echo "--- Project $((i + 1)) ---"

  # project_key
  KEY=$(yq ".jfrog_projects[$i].project_key // \"\"" "$MANIFEST")
  if [ -z "$KEY" ] || [ "$KEY" = "null" ]; then
    echo "ERROR: jfrog_projects[$i].project_key is missing"
    ERRORS=$((ERRORS + 1))
  elif ! echo "$KEY" | grep -qE '^[a-z][a-z0-9]{2,31}$'; then
    echo "ERROR: jfrog_projects[$i].project_key '$KEY' is invalid (must be 3-32 lowercase alphanumeric, starting with a letter)"
    ERRORS=$((ERRORS + 1))
  else
    echo "OK: project_key = $KEY"
  fi

  # github_repos (list)
  REPO_COUNT=$(yq ".jfrog_projects[$i].github_repos | length" "$MANIFEST")
  if [ "$REPO_COUNT" -eq 0 ] || [ "$REPO_COUNT" = "null" ]; then
    echo "ERROR: jfrog_projects[$i].github_repos is missing or empty"
    ERRORS=$((ERRORS + 1))
  else
    for j in $(seq 0 $((REPO_COUNT - 1))); do
      REPO=$(yq ".jfrog_projects[$i].github_repos[$j]" "$MANIFEST")
      if ! echo "$REPO" | grep -qE '^[a-zA-Z0-9._-]+/[a-zA-Z0-9._-]+$'; then
        echo "ERROR: jfrog_projects[$i].github_repos[$j] '$REPO' is not in owner/repo format"
        ERRORS=$((ERRORS + 1))
      fi
    done
    echo "OK: github_repos = $(yq ".jfrog_projects[$i].github_repos | join(\", \")" "$MANIFEST")"
  fi

  # ecosystems
  ECO_COUNT=$(yq ".jfrog_projects[$i].ecosystems | length" "$MANIFEST")
  if [ "$ECO_COUNT" -eq 0 ]; then
    echo "WARNING: jfrog_projects[$i].ecosystems is empty"
  else
    for j in $(seq 0 $((ECO_COUNT - 1))); do
      ECO=$(yq ".jfrog_projects[$i].ecosystems[$j]" "$MANIFEST")
      if ! echo "$VALID_ECOSYSTEMS" | grep -qw "$ECO"; then
        echo "ERROR: jfrog_projects[$i].ecosystems[$j] '$ECO' is not valid (must be one of: $VALID_ECOSYSTEMS)"
        ERRORS=$((ERRORS + 1))
      fi
    done
    echo "OK: ecosystems = $(yq ".jfrog_projects[$i].ecosystems | join(\", \")" "$MANIFEST")"
  fi

  # display_name
  DISPLAY=$(yq ".jfrog_projects[$i].display_name // \"\"" "$MANIFEST")
  if [ -z "$DISPLAY" ] || [ "$DISPLAY" = "null" ]; then
    echo "WARNING: jfrog_projects[$i].display_name is missing (will use project_key)"
  else
    echo "OK: display_name = $DISPLAY"
  fi
done

echo ""
echo "================================"
if [ "$ERRORS" -gt 0 ]; then
  echo "FAILED: $ERRORS error(s) found"
  exit 1
else
  echo "PASSED: All validations passed"
  exit 0
fi
