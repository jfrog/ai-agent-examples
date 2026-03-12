#!/usr/bin/env bash
# JFrog Artifactory Go module proxy configuration
# Source this file or add these exports to your shell profile.
# Replace {username} and {password} with your JFrog credentials.

export GOPROXY="https://{username}:{password}@{{JFROG_HOSTNAME}}/artifactory/api/go/{{PROJECT_KEY}}-go,direct"
export GONOSUMDB="github.com/{{ORG_NAME}}/*"
