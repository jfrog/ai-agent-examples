#!/usr/bin/env bash
# detect-ecosystem.sh -- Auto-detect package ecosystems in a GitHub repository
# Usage: ./scripts/detect-ecosystem.sh <owner/repo> [github-host]
#
# Clones the repo (shallow, depth 1) into a temp directory and inspects
# the repo contents to detect which ecosystems are in use based on marker files.
#
# Arguments:
#   owner/repo    -- GitHub repository in owner/repo format
#   github-host   -- (optional) GitHub host URL (default: https://github.com)
#
# Output: space-separated list of detected ecosystems (e.g., "npm docker")

set -euo pipefail

REPO="${1:?Usage: $0 <owner/repo> [github-host]}"
GITHUB_HOST="${2:-https://github.com}"
DETECTED=()

echo "Detecting ecosystems in $REPO..." >&2

# Clone the repo into a temp directory (shallow, depth 1)
TMPDIR=$(mktemp -d)
trap "rm -rf $TMPDIR" EXIT

if ! git clone --depth 1 --quiet "${GITHUB_HOST}/${REPO}.git" "$TMPDIR/repo" 2>/dev/null; then
  echo "ERROR: Failed to clone ${GITHUB_HOST}/${REPO}.git" >&2
  exit 1
fi

# Helper: check if a file exists in the cloned repo
file_exists() {
  local path="$1"
  [ -f "$TMPDIR/repo/$path" ]
}

# npm / Node.js
if file_exists "package.json"; then
  DETECTED+=("npm")
  echo "  Found package.json -> npm" >&2
fi

# Maven
if file_exists "pom.xml"; then
  DETECTED+=("maven")
  echo "  Found pom.xml -> maven" >&2
fi

# Gradle (also Java/Kotlin ecosystem, uses maven repos)
if file_exists "build.gradle" || file_exists "build.gradle.kts"; then
  if [[ ! " ${DETECTED[*]} " =~ " maven " ]]; then
    DETECTED+=("maven")
    echo "  Found build.gradle -> maven (Gradle uses Maven repos)" >&2
  fi
fi

# Python / pip
if file_exists "requirements.txt" || file_exists "pyproject.toml" || file_exists "setup.py"; then
  DETECTED+=("pip")
  if file_exists "requirements.txt"; then
    echo "  Found requirements.txt -> pip" >&2
  elif file_exists "pyproject.toml"; then
    echo "  Found pyproject.toml -> pip" >&2
  else
    echo "  Found setup.py -> pip" >&2
  fi
fi

# Go
if file_exists "go.mod"; then
  DETECTED+=("go")
  echo "  Found go.mod -> go" >&2
fi

# Docker
if file_exists "Dockerfile"; then
  DETECTED+=("docker")
  echo "  Found Dockerfile -> docker" >&2
fi

# Helm
if file_exists "Chart.yaml"; then
  DETECTED+=("helm")
  echo "  Found Chart.yaml -> helm" >&2
fi

if [ ${#DETECTED[@]} -eq 0 ]; then
  echo "  No recognized ecosystems detected" >&2
  echo ""
else
  echo "" >&2
  echo "Detected ecosystems: ${DETECTED[*]}" >&2
  echo "${DETECTED[*]}"
fi
