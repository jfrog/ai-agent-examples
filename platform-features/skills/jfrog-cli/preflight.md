# Pre-flight Service Discovery

Run this check **once per session** after login, **platform URL confirmation**, and **readiness** (Steps 1b–1c and Step 2 of [login-flow.md](login-flow.md)) to discover which JFrog services are available. This avoids wasting time calling APIs for services that are not deployed on the target instance.

## When to Run

- Before any multi-service workflow (onboarding, pattern setup, journey execution)
- After switching environments with `jf config use`
- When the user asks "what can I do?" and the agent needs to filter suggestions

Skip this if the session only uses Artifactory (repos, artifacts, builds) -- Artifactory is always available.

## Pre-flight script

Prefer **`jf api`** (see [jf-api-patterns.md](jf-api-patterns.md)); use **`--server-id="$JFROG_SERVER_ID"`** when required. Run service pings in a **single parallel batch** (independent calls). Capture **stdout** (body) and **stderr** (HTTP code) per call when you need status codes.

```bash
# Artifactory version (always available)
jf api /artifactory/api/system/version

# Xray
jf api /xray/api/v1/system/ping >/tmp/jf-pf-xray.body 2>/tmp/jf-pf-xray.code
# tr -d '\r\n' < /tmp/jf-pf-xray.code  → expect 200

# Lifecycle (Release Bundles / RLM)
jf api "/lifecycle/api/v2/promotion/records?limit=1" >/tmp/jf-pf-lc.body 2>/tmp/jf-pf-lc.code

# AppTrust (requires explicit --server-id)
jf apptrust ping --server-id="$JFROG_SERVER_ID" 2>&1

# Curation
jf api /curation/api/v1/system/ping >/tmp/jf-pf-cur.body 2>/tmp/jf-pf-cur.code

# User admin status (use a non-reserved variable name, e.g. JFROG_USER_NAME — not USERNAME)
jf api "/artifactory/api/security/users/${JFROG_USER_NAME}"

# Existing projects
jf api /access/api/v1/projects
```

**Fallback** (no CLI or CLI older than 2.100.0): same paths with `curl` and `Authorization: Bearer $JFROG_ACCESS_TOKEN` against `$JFROG_URL`.

## Interpreting Results

| Service | Available if | Variable to set |
|---------|-------------|-----------------|
| Artifactory | Ping returns `OK` (always expected) | -- |
| Xray | Ping returns HTTP 200 | `JFROG_HAS_XRAY=true` |
| Lifecycle | Returns HTTP 200 (even with empty results) | `JFROG_HAS_LIFECYCLE=true` |
| AppTrust | `jf apptrust ping --server-id` prints `OK` | `JFROG_HAS_APPTRUST=true` |
| Curation | Ping returns HTTP 200 | `JFROG_HAS_CURATION=true` |
| Admin | User JSON has `"admin": true` | `JFROG_IS_ADMIN=true` |

## What to Do with Results

1. **Report to the user** with a short summary table (service name + OK / NOT AVAILABLE).
2. **Filter downstream suggestions.** When using [flow-suggestions.md](../jfrog-patterns/flow-suggestions.md), only offer paths for available services.
3. **Stop early** if a required service is missing. Example: if the user asks for AppTrust setup but `JFROG_HAS_APPTRUST` is false, inform them immediately instead of attempting API calls.
4. **Note admin status.** Operations that create projects, users, or lifecycle stages require admin privileges. If `JFROG_IS_ADMIN` is false, warn the user before attempting privileged operations.
