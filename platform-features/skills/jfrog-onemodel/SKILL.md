---
name: jfrog-onemodel
description: >-
  Query any entity on the JFrog Platform using OneModel GraphQL — applications,
  release bundles, artifacts, builds, evidence, packages, and catalog data
  through a single unified API. Use this skill when the user wants to query,
  search, or list anything from the JFrog Platform using GraphQL, including
  applications, application versions, release bundles, artifacts, evidence,
  packages, catalog information, or build traceability. Also use when the user
  asks "what do I have" or "list my..." for JFrog Platform entities. Triggers
  on mentions of "onemodel", "graphql", "release bundle info", "evidence
  query", "search evidence", "release bundle artifacts", "build traceability",
  "graphql query jfrog", "run a graphql query against jfrog", "list
  applications", "my applications", "search packages", or "catalog info".
alwaysApply: false
---


> **API transport:** Prefer **`jf api`** (JFrog CLI 2.100.0+). See [jf-api-patterns.md](../jfrog-cli/jf-api-patterns.md) (path-only URLs; auth from `jf config`). Examples using **`curl`** with `$JFROG_URL` + bearer token are **fallback** when the CLI is missing or below 2.100.0.

# JFrog OneModel

Run OneModel GraphQL queries against the JFrog Platform to fetch information about applications, release bundles, artifacts, builds, evidence, packages, and more through the unified OneModel endpoint.

## Prerequisites

- **"jfrog-cli" skill** — this skill depends on the sibling "jfrog-cli" skill for CLI installation and server configuration. Ensure it is installed.
- **JFrog CLI** (`jf`) configured with at least one server — needed to resolve the JFrog Platform URL and access token.
- **Artifactory 7.104.1+** — OneModel GraphQL requires this minimum version.
- **Access token** with wildcard audience (`*@*`) — the token must be scoped to the content being queried.

## Workflow

Follow these steps in order. Skipping the schema fetch (step 2) is the most common source of errors — queries built from assumptions or cached knowledge will fail on servers whose schema differs from what you expect.

1. **Resolve credentials** — get JFrog URL and access token
2. **Fetch the schema** — always fetch the supergraph schema from the server
3. **Understand the query intent** — map the user's request to available domains and types
4. **Construct the GraphQL query** — build the query based on the resolved schema
5. **Validate the query against the schema** — verify every field and type before executing
6. **Execute the query** — POST to the OneModel endpoint
7. **Handle the response** — paginate if needed, present results clearly


### 1. Resolve Credentials

Get the JFrog Platform URL and access token from the JFrog CLI configuration.

First, identify the server ID to use. List configured servers with:
```bash
jf config show
```

If the user did not specify a server, use the one marked `Default: true`.
If no server is configured, refer to the "jfrog-cli" skill's login flow.

Then extract the URL and access token using `jf config export`:
```bash
JFROG_URL=$(jf config export <server-id> | base64 -d | jq -r .url)
JFROG_URL=${JFROG_URL%/}
JFROG_ACCESS_TOKEN=$(jf config export <server-id> | base64 -d | jq -r .accessToken)
```

Replace `<server-id>` with the actual server ID (e.g. `mycompany`).
On older macOS versions where `base64 -d` is not recognized, use
`base64 -D` (capital D) or `base64 --decode` instead.

The `${JFROG_URL%/}` trim removes a trailing `/` if present, preventing double-slash URLs (e.g. `https://example.jfrog.io//onemodel/...`) when the URL is later concatenated with absolute paths like `/onemodel/api/v1/graphql`.

If the above fails, ask the user for the URL and token directly, or check environment variables `JFROG_URL` and `JFROG_ACCESS_TOKEN`.


### 2. Fetch the Schema

**This step is mandatory.** You need the supergraph schema from the specific JFrog server you are working with.

The schema is large. To avoid refetching it on every query, cache it to a local file keyed by server ID. Check for the cached file first:

```bash
SCHEMA_FILE=".jfrog/local/onemodel-schema-<server-id>.graphql"
```

If the file already exists, read it from disk. Otherwise, fetch and save it:

```bash
mkdir -p .jfrog/local
curl -s -X GET \
  -H "Authorization: Bearer $JFROG_ACCESS_TOKEN" \
  "$JFROG_URL/onemodel/api/v1/supergraph/schema" \
  -o "$SCHEMA_FILE"
```

Replace `<server-id>` with the actual server ID used in step 1. The cached schema is valid for the duration of a session — no need to refetch unless you switch to a different server.

If the fetch fails (HTTP 401/403, empty file, or network error), verify that the access token is valid and has wildcard audience (`*@*`), the URL is correct (no trailing path), and the server runs Artifactory 7.104.1+. If the schema file is empty or contains an HTML error page, delete it and retry.

The schema file contains the complete GraphQL schema definition (SDL) — the list of available domains (namespaces), types, fields, query arguments, enums, and directives.

#### Navigating the schema

The schema is large (typically 10,000+ lines). Do not attempt to read it in full. Instead, use targeted searches:

1. **Find available namespaces** — search for lines matching `: ...Queries!` near the root `Query` definition. Each match is a top-level namespace (e.g. `applications: ApplicationsQueries!`).
2. **Find operations for a namespace** — search for the `...Queries` type name (e.g. `ApplicationsQueries`) to see its `get...` and `search...` methods.
3. **Find input/filter types** — from the operation signature, look up the `WhereInput` type (e.g. `ApplicationWhereInput`) to see available filters.
4. **Find output fields** — look up the node type (e.g. `Application`) to see which fields you can request.

When reading the schema, **ignore any types and fields annotated with the `@inaccessible` directive.** These are internal federation artifacts that are not queryable through the OneModel endpoint. Only use types and fields that are not marked `@inaccessible`.

#### Never assume — always verify in the schema

**Before constructing any query, look up every type you intend to use.** Do not guess based on naming conventions, examples, or prior knowledge. Common mistakes that waste round-trips:

- **Scalars vs enums** — A type like `PackageType` may look like an enum but actually be a `scalar` (a string). Search for the type definition (e.g. `scalar PackageType` or `enum PackageType`) to know whether to pass a bare identifier (`NPM`) or a quoted string (`"npm"`). The description line above the scalar often contains example values — read it.
- **Connection fields vs plain fields** — GraphQL connections use the naming pattern `...Connection` (e.g. `vulnerabilitiesConnection`), not bare field names (e.g. `vulnerabilities`). Always look up the parent type to find the exact field name and its required arguments.
- **Nested type structure** — When a field returns a complex type (e.g. `securityInfo: PublicPackageVersionSecurityInfo`), you must search for that type's definition to discover its subfields. Do not assume the subfield names.

#### Read the descriptions — they carry semantic meaning

Schema descriptions (the `"""..."""` doc strings above types, fields, and arguments) are not just documentation — they encode critical semantic information about how the schema works:

- **Scalar descriptions** often include example values and formatting rules (e.g. `PackageType` description says `Example: "npm"`, revealing it takes a lowercase quoted string).
- **Field descriptions** clarify what a field represents and how it relates to other fields (e.g. a vulnerability's `ecosystem` field describes the advisory source like "redhat" or "debian", not the package type — reading the description prevents confusing it with the package ecosystem).
- **Filter descriptions** explain matching behavior (e.g. "matched with fold operation" means case-insensitive matching).
- **Argument descriptions** specify constraints like maximum page sizes, mutual exclusivity, and default behaviors.

When you look up a type or field, always read the surrounding description lines (typically 3–5 lines above the definition). This takes seconds and prevents costly wrong assumptions.

**Why this is required:** The OneModel schema is a federated supergraph that is dynamically composed based on the products, entitlements, and license of the specific JFrog server. Different servers expose different domains and types. For example, one server may include evidence types while another may not. You cannot assume which domains or fields exist — the resolved schema is the only reliable source of truth.

**Do NOT rely on:**
- Public documentation — it is incomplete and does not cover all domains, entities, and types.
- Hardcoded query examples — they are illustrative patterns, not guaranteed to work on every server.
- The legacy metadata GraphiQL (`/metadata/api/v1/query/graphiql`) — it is deprecated and does not reflect the OneModel schema.


### 3. Understand the Query Intent

Using the resolved schema from step 2, map the user's request to the available domains and types. Search the schema file for the root `Query` type — look for lines containing `: ...Queries!` to discover which namespaces exist on this server.

Common domains you may find (but always verify in the schema):
- **Applications** — applications, application versions, bound package versions
- **Release Lifecycle** — release bundle versions, artifacts, source builds
- **Evidence** — evidence attached to artifacts, repos, or release bundles
- **Stored Packages** — packages and package versions stored in Artifactory repositories
- **Public Packages** — packages from public registries (npm, Maven Central, etc.)
- **Custom Catalog** — catalog packages, labels, security info, legal info

To verify whether a domain exists for the user's request, search the schema file (case-insensitive) for keywords related to their request. If no matching types or namespaces appear, the server does not support that capability — inform the user.

If the user's intent is unclear, list the available top-level namespaces from the schema and ask which domain they need.

**Note:** The legacy metadata GraphQL (`packages` root query at `/metadata/api/v1/query`) is deprecated and NOT part of OneModel. Do not use the `packages` query through the OneModel endpoint.


### 4. Construct the GraphQL Query

Build the query using **only** types, fields, and arguments that exist in the resolved schema from step 2. Do not guess field names or assume types exist.

#### Pre-construction checklist

Before writing any query, look up each of these in the schema file. Do not skip any step — each prevents a distinct class of errors:

1. **Look up every argument type** — for each argument you plan to pass (e.g. `type`, `where`, `orderBy`), search the schema for its type definition. Check whether it is a `scalar`, `enum`, or `input` type. Read its description to understand accepted values and formatting.
2. **Look up every output type** — for each field you plan to select, search the schema for the type it returns. Read its fields and descriptions to know which subfields exist and what they mean. Pay attention to `...Connection` vs direct fields.
3. **Look up every filter input** — for `WhereInput` types, read all available filter fields and their descriptions. This reveals what filtering is possible and prevents using non-existent filters.
4. **Verify field paths end-to-end** — trace the full path from root to leaf (e.g. `publicPackages` → `searchPackages` → `edges` → `node` → `latestVersion` → `securityInfo` → `vulnerabilitiesConnection`) and confirm each hop exists in the schema with the exact field name.

#### Principles

- **Aim for a single query** — construct one query that returns all the data the user needs, including nested fields and filters. Minimize the total number of round-trips to the server. If the pre-construction checklist above was followed, the first query should succeed.
- **Request only needed fields** — don't fetch everything; ask for what the user needs to minimize response size and improve performance.
- **Fall back to a minimal query on failure** — if a query fails with a validation error or returns unexpected empty results, strip it down to a lightweight version (e.g. just `name` and `totalCount`) to isolate which filter or field is wrong. Fix the issue and retry with the full query.
- **Use filters** — apply `where` arguments directly in the query rather than fetching everything and filtering client-side.
- **Use pagination** — always include `first` for large result sets. Include `pageInfo { hasNextPage endCursor }` to enable follow-up pages.
- **Use variables** for dynamic values to keep queries clean and reusable.

Read [references/query-examples.md](references/query-examples.md) for illustrative query patterns. These are examples of common shapes — always verify the actual field names and types against the resolved schema before use.

Read [references/common-patterns.md](references/common-patterns.md) for general GraphQL patterns (pagination, variables, date formatting) that apply regardless of which domains are available.

#### Query Naming Convention

OneModel uses a consistent naming pattern:
- `get...` — returns a single item (e.g. `getVersion`, `getEvidence`)
- `search...` — returns a list of items (e.g. `searchEvidence`)


### 5. Validate the Query Against the Schema

**After constructing the query and before executing it**, re-read the query and verify every identifier against the schema file. This catches errors that are easy to introduce during construction — wrong field names, missing subfield selections, incorrect argument types — and avoids wasted round-trips.

Walk through the query from root to leaf and check each of the following:

1. **Every field name is spelled exactly as in the schema.** Search the schema for each field you reference. Pay attention to casing and suffixes (e.g. `preferredBaseScore` not `preferredScore`, `vulnerabilitiesConnection` not `vulnerabilities`).
2. **Every field that returns an object type has a subfield selection.** If a field returns a type (not a scalar), you must select at least one subfield inside `{ ... }`. Missing selections produce a validation error.
3. **Every argument value matches the expected type.** For each argument:
   - If the schema defines it as a `scalar` (e.g. `PackageType`), pass a quoted string (e.g. `"maven"`).
   - If the schema defines it as an `enum` (e.g. `PublicVulnerabilitySeverityLevel`), pass a bare identifier (e.g. `CRITICAL`).
   - If the schema defines it as an `input` type, verify that every nested field you pass exists in that input type.
4. **Every filter path is valid end-to-end.** Trace nested `where` filters through each `WhereInput` type to confirm the chain exists. For example, `hasPublicPackageVersionWith` → `hasSecurityInfoWith` →
   `hasVulnerabilitiesWith` → `severity: CRITICAL` — each hop must exist in the corresponding input type.
5. **Connection fields include pagination arguments.** Every `...Connection` field should have `first` (or `last`) to control page size.

If any identifier cannot be confirmed in the schema, look it up now before proceeding to execution. Fixing a field name in the query is instant; waiting for an HTTP round-trip to discover the error is not.


### 6. Execute the Query

POST the query to the unified OneModel endpoint.

#### Always save the response to a file

**Always** save the raw response to a local file before processing it — use `curl -o "$RESPONSE_FILE"` so the response is written directly to disk. This avoids unnecessary re-requests — if the response handling or parsing needs to be adjusted (e.g. extracting different fields, fixing a `jq` filter, or reformatting output), you can re-read the saved file instead of re-sending the same query to the server. **Never pipe `curl` output to `jq` directly** — if the `jq` filter is wrong, the response is lost and must be re-fetched.

Create a temp directory once per session and number each response file sequentially so that parallel processes get isolated directories and sequential queries within the same process never overwrite each other:

```bash
# Run once per session (before the first query)
ONEMODEL_TMPDIR=$(mktemp -d)
ONEMODEL_QUERY_NUM=0
```

Then, before each query:
```bash
ONEMODEL_QUERY_NUM=$((ONEMODEL_QUERY_NUM + 1))
RESPONSE_FILE="$ONEMODEL_TMPDIR/response-$ONEMODEL_QUERY_NUM.json"
```

#### Always use `jq` to build the JSON payload

**Do not** manually embed the GraphQL query string inside a JSON literal with escaped quotes. GraphQL queries contain double quotes (for string arguments like `"maven"`) and deeply nested structures that make manual escaping error-prone — a single missed or extra `\"` corrupts the entire request, often producing cryptic errors (HTTP 400, empty responses, or malformed JSON).

Instead, store the GraphQL query in a shell variable and use `jq -n --arg` to safely construct the JSON payload. Use `-o "$RESPONSE_FILE"` to write the response to disk, then read it with `jq`:

```bash
QUERY='{ publicPackages { searchPackages(where: { type: "maven" }, first: 5) { totalCount edges { node { name } } } } }'

PAYLOAD=$(jq -n --arg q "$QUERY" '{"query": $q}')

ONEMODEL_QUERY_NUM=$((ONEMODEL_QUERY_NUM + 1))
RESPONSE_FILE="$ONEMODEL_TMPDIR/response-$ONEMODEL_QUERY_NUM.json"

curl -s -X POST \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $JFROG_ACCESS_TOKEN" \
  "$JFROG_URL/onemodel/api/v1/graphql" \
  -d "$PAYLOAD" \
  -o "$RESPONSE_FILE"

jq . "$RESPONSE_FILE"
```

This approach keeps the GraphQL query readable (no `\"` escaping needed) and lets `jq` handle all JSON encoding automatically.

When using variables, add them with additional `--arg` flags:
```bash
QUERY='query GetEvidence($repo: String!) { evidence { searchEvidence(where: { hasSubjectWith: { repositoryKey: $repo } }) { totalCount } } }'

PAYLOAD=$(jq -n \
  --arg q "$QUERY" \
  --arg repo "my-repo-local" \
  '{"query": $q, "variables": {"repo": $repo}}')

ONEMODEL_QUERY_NUM=$((ONEMODEL_QUERY_NUM + 1))
RESPONSE_FILE="$ONEMODEL_TMPDIR/response-$ONEMODEL_QUERY_NUM.json"

curl -s -X POST \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $JFROG_ACCESS_TOKEN" \
  "$JFROG_URL/onemodel/api/v1/graphql" \
  -d "$PAYLOAD" \
  -o "$RESPONSE_FILE"

jq . "$RESPONSE_FILE"
```

### 7. Handle the Response

The response is saved in `$RESPONSE_FILE` (set in step 6). **Always read from this file** when processing, formatting, or re-processing the response — never re-execute the query just to adjust parsing or presentation.

If you need to extract different fields, fix a `jq` filter, or reformat output, re-read `$RESPONSE_FILE`:
```bash
jq '.data.publicPackages.searchPackages.edges[].node.name' "$RESPONSE_FILE"
```

#### Success Response

A successful response has this structure:
```json
{
  "data": {
    "<namespace>": {
      "<queryName>": { ... }
    }
  }
}
```

#### Error Response

Errors appear in an `errors` array:
```json
{
  "errors": [
    {
      "message": "...",
      "path": ["..."],
      "extensions": { "code": "..." }
    }
  ]
}
```

Common errors and fixes:

| Error | Cause | Fix |
|-------|-------|-----|
| `401 Bad Credentials` | Invalid or expired token | Refresh the access token |
| `403 Permission Denied` | Insufficient permissions | Check user has read access to the queried resource |
| `GRAPHQL_VALIDATION_FAILED` | Invalid query syntax or fields | Fetch the schema via `GET /onemodel/api/v1/supergraph/schema` and verify field names |
| Empty results | Filter too restrictive or no data | Broaden filters or verify the data exists |

#### Pagination

If `pageInfo.hasNextPage` is `true`, fetch the next page using the `endCursor` value as the `after` argument. Repeat until `hasNextPage` is `false`. Each page fetch increments the counter and saves to a separate file (`response-1.json`, `response-2.json`, etc.).

Read [references/common-patterns.md](references/common-patterns.md) for detailed pagination patterns.

#### Presenting Results

- Summarize the data in a clear format (table, bullet list, or structured text)
- Highlight key findings relevant to the user's original question
- If the result set is very large, offer to paginate or filter further


## Gotchas

- **The schema varies per server.** The OneModel supergraph is dynamically composed based on the server's products, entitlements, and license. Never assume a domain, type, or field exists — always verify against the resolved schema from `GET /onemodel/api/v1/supergraph/schema`.
- **Public documentation is incomplete.** Not all domains, entities, and types are documented. The resolved schema is the only reliable source of truth.
- **Ignore `@inaccessible` types and fields.** The supergraph schema includes internal federation artifacts marked `@inaccessible` — these cannot be queried. Only use types and fields that are not marked with this directive.
- **Scalars look like enums but are not.** Types like `PackageType` are `scalar` (string), not `enum`. Passing a bare identifier (e.g. `NPM`) instead of a quoted string (e.g. `"npm"`) will silently return zero results rather than an error. Always search the schema for the type definition and read its description for example values before using it.
- **Read schema descriptions.** The `"""..."""` doc strings above types and fields encode semantic meaning — accepted values, matching behavior, constraints, and relationships between fields. Skipping descriptions is a common source of wrong assumptions (e.g. confusing a vulnerability's advisory `ecosystem` with the package type).
- The OneModel endpoint is `/onemodel/api/v1/graphql`. Do NOT use the legacy metadata endpoint (`/metadata/api/v1/query`) or its `packages` root query — they are deprecated and not part of OneModel.
- Do NOT use the legacy metadata GraphiQL (`/metadata/api/v1/query/graphiql`) for schema discovery — it is deprecated and does not reflect the OneModel schema.
- Token audience MUST be wildcard (`*@*`). Scoped tokens without wildcard audience will fail with authentication errors.
- `jf rt curl` only works for Artifactory REST API paths (under `/artifactory/`). For OneModel, use regular `curl` with the platform base URL.
- GraphQL queries must be sent as POST with `Content-Type: application/json`.
- `first/after` (forward) and `last/before` (backward) pagination are mutually exclusive — never mix them in the same query.
- Date fields ending in `...At` (e.g. `createdAt`) default to ISO-8601 UTC. Use the `@dateFormat` directive to change the format.
- Fields marked `@experimental` may change in future releases.
- Fields marked `@deprecated` will be removed — migrate away from them.
- **Always use `curl -o "$RESPONSE_FILE"`** to save responses to disk. Never pipe curl directly to `jq` — if the filter is wrong, the response is lost and the query must be re-executed. Save first, then process from the file.


## Reference Files

- [query-examples.md](references/query-examples.md) — Read when constructing queries; contains ready-to-use templates for applications, stored packages, public packages, release lifecycle, and evidence domains
- [common-patterns.md](references/common-patterns.md) — Read when working with pagination, filtering, ordering, date formatting, or variables
- [graphql-playground.md](references/graphql-playground.md) — Read when the user wants to explore interactively, asks about a UI for GraphQL, or multiple query attempts have failed. Also contains official documentation links
