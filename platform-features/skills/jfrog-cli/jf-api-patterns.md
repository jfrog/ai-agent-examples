# `jf api` patterns (JFrog CLI 2.100.0+)

Use **`jf api`** as the **preferred** way to invoke JFrog Platform REST APIs. It uses the **configured server** from `jf config` (URL and credentials); you pass **path only** (e.g. `/access/api/v2/users`), not a full `https://...` URL.

**Requirements:** [Install JFrog CLI](https://docs.jfrog.com/integrations/docs/download-and-install-the-jfrog-cli) **v2.100.0 or newer**. Complete [login-flow.md](login-flow.md) first.

## Session start: confirm platform, then readiness

1. Run **`jf config show`** and **present each server id and URL** to the user.
2. Ask **one question** (per [interaction-questions.mdc](../../../global/rules/interaction-questions.mdc)) to **confirm** this is the correct JFrog instance, or have them switch with `jf config use <server-id>` / add a server.
3. After confirmation, validate connectivity:
   ```bash
   BODY=/tmp/jf-readiness.json
   CODE=/tmp/jf-readiness.code
   jf api /artifactory/api/v1/system/readiness >"$BODY" 2>"$CODE"
   HTTP_CODE=$(tr -d '\r\n' < "$CODE")
   ```
   Expect **HTTP 200**. Use **`--server-id=<id>`** if the default server is not the one the user chose.
4. Continue with auth/admin checks (e.g. `/artifactory/api/system/version`) as needed.

## How `jf api` behaves

- **Stdout:** response body.
- **Stderr:** a single line with the **HTTP status code**.
- **Exit code:** `0` on success (2xx); **non-zero** on failure (non-2xx still prints the body).

Always **capture stdout and stderr separately** before piping the body to `jq`. Never `jf api ... | jq` without checking status first.

## Capture body and HTTP status

```bash
BODY=/tmp/jf-api-out.json
CODE=/tmp/jf-api-out.code
jf api /access/api/v1/projects >"$BODY" 2>"$CODE"
HTTP_CODE=$(tr -d '\r\n' < "$CODE")

if [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "201" ]; then
  jq '.' "$BODY"
else
  echo "ERROR: HTTP $HTTP_CODE"
  cat "$BODY"
fi
```

Use **unique** `/tmp/...` names in loops.

## Methods, headers, and body

```bash
# GET (default)
jf api /artifactory/api/repositories

# POST JSON from file
jf api /access/api/v2/users -X POST -H "Content-Type: application/json" --input ./user.json

# POST JSON inline
jf api /access/api/v2/users -X POST -H "Content-Type: application/json" \
  -d '{"username":"newuser","email":"newuser@example.com","password":"UseASecurePassword123"}'

# PUT / DELETE
jf api /artifactory/api/repositories/my-repo -X DELETE

# Timeout (seconds)
jf api /artifactory/api/repositories --timeout 30
```

## Multiple servers

```bash
jf api /artifactory/api/system/version --server-id=mycompany
```

## When to use `curl` instead

Use **`curl`** with `$JFROG_URL` and `Authorization: Bearer $JFROG_ACCESS_TOKEN` only when:

- JFrog CLI is **not installed** or is **below 2.100.0**, or
- There is **no** `jf config` yet (e.g. bootstrap steps in web login **before** `jf config add`), or
- The user explicitly requires env-token-only access.

Follow safe patterns in [jfrog-platform.mdc](../../../global/rules/jfrog-platform.mdc).

## References

- [login-flow.md](login-flow.md) -- install, `jf config`, web login
- [preflight.md](preflight.md) -- service discovery after login
- JFrog REST APIs: [Platform REST APIs](https://jfrog.com/help/r/jfrog-platform-documentation/rest-apis) (linked from CLI help text)
