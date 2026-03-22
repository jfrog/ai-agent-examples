# OneModel GraphQL Common Patterns

General GraphQL patterns and conventions that apply across OneModel domains.
These patterns (pagination, variables, date formatting) are stable regardless of which specific domains are available on a given server. Always verify concrete field names and filter arguments against the resolved schema from `GET /onemodel/api/v1/supergraph/schema`.

## Pagination

OneModel uses cursor-based pagination following the Relay specification.

### Forward Pagination

Use `first` (page size) and `after` (cursor) to page forward through results.

```graphql
query {
  evidence {
    searchEvidence(
      first: 20
      after: "<endCursor-from-previous-page>"
      where: { hasSubjectWith: { repositoryKey: "my-repo" } }
    ) {
      edges {
        node {
          predicateSlug
          verified
        }
        cursor
      }
      pageInfo {
        hasNextPage
        endCursor
      }
    }
  }
}
```

**To fetch all pages:**
1. First request: omit `after` to get the first page
2. Check `pageInfo.hasNextPage` — if `true`, fetch the next page
3. Pass `pageInfo.endCursor` as the `after` value in the next request
4. Repeat until `hasNextPage` is `false`

### Backward Pagination

Use `last` (page size) and `before` (cursor) to page backward.

```graphql
searchEvidence(last: 10, before: "<cursor>") { ... }
```

**Rules:**
- `first/after` and `last/before` are mutually exclusive
- If no pagination arguments are provided, the first page is returned with the query's default page size
- `after` is optional for forward pagination (omit for first page)


## Filtering

Use `where` arguments to narrow query results. Always check the specific query's schema (via `GET /onemodel/api/v1/supergraph/schema`) for available filter fields.

### Evidence Domain

Uses the `where` argument with `hasSubjectWith` to filter by artifact location:

```graphql
searchEvidence(
  where: {
    hasSubjectWith: {
      repositoryKey: "my-repo"
      path: "path/to"
      name: "file.ext"
    }
  }
) { ... }
```

### Applications Domain

Uses the `where` argument with fields like `projectKey`, `nameContains`,
`criticality`, and `maturityLevel`:

```graphql
searchApplications(
  where: {
    projectKey: "my-project"
    nameContains: "store"
    criticality: "high"
  }
  first: 25
) { ... }
```

### Stored Packages Domain

Uses the `where` argument with `type` (required) and optional filters like `name` and `projectKey`:

```graphql
searchPackages(
  where: { type: "docker", name: "my-image" }
  first: 20
) { ... }
```

### Public Packages Domain

Uses the `where` argument with `type` and optional `nameContains`:

```graphql
searchPackages(
  where: { type: "npm", nameContains: "lodash" }
  first: 20
) { ... }
```

### Release Lifecycle Domain

Uses `where` on connection fields:

```graphql
artifactsConnection(
  first: 50
  where: { hasEvidence: true }
) { ... }
```


## Ordering

Use the `orderBy` argument where supported:

```graphql
searchEvidence(
  first: 20
  orderBy: { field: CREATED_AT, direction: DESC }
  where: { hasSubjectWith: { repositoryKey: "my-repo" } }
) { ... }
```

- `field` — the field to sort by
- `direction` — `ASC` or `DESC`

Not all queries support `orderBy` — check the schema for each query.


## Variables

Use GraphQL variables for dynamic values instead of string interpolation. This makes queries cleaner and avoids escaping issues.

### Query Definition

```graphql
query GetEvidence($repoKey: String!, $path: String!, $name: String!) {
  evidence {
    getEvidence(
      repositoryKey: $repoKey
      path: $path
      name: $name
    ) {
      id
      verified
    }
  }
}
```

### cURL with Variables

Always use `jq -n` to build the JSON payload — never manually escape quotes inside the query string:

```bash
QUERY='query GetEvidence($repoKey: String!, $path: String!, $name: String!) { evidence { getEvidence(repositoryKey: $repoKey, path: $path, name: $name) { id verified } } }'

PAYLOAD=$(jq -n \
  --arg q "$QUERY" \
  --arg repoKey "example-repo-local" \
  --arg path "path/to" \
  --arg name "file.ext" \
  '{"query": $q, "variables": {"repoKey": $repoKey, "path": $path, "name": $name}}')

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


## Date Formatting

Fields ending in `...At` (e.g. `createdAt`, `modifiedAt`) return timestamps in ISO-8601 UTC by default: `2024-11-05T13:15:30.972Z`

Use the `@dateFormat` directive to change the format:

```graphql
query {
  evidence {
    searchEvidence(first: 5) {
      edges {
        node {
          createdAt @dateFormat(format: DD_MMM_YYYY)
        }
      }
    }
  }
}
```

Available formats:
- Default (no directive): `2024-11-05T13:15:30.972Z` (ISO-8601 UTC)
- `DD_MMM_YYYY`: `05 Nov 2024`
- `ISO8601_DATE_ONLY`: `2024-11-05`


## Response Structure

### Successful Response

```json
{
  "data": {
    "<namespace>": {
      "<queryName>": {
        "edges": [
          {
            "node": { ... },
            "cursor": "abc123"
          }
        ],
        "pageInfo": {
          "hasNextPage": true,
          "endCursor": "abc123"
        },
        "totalCount": 42
      }
    }
  }
}
```

- `edges` — array of results, each with a `node` (the data) and optional `cursor`
- `pageInfo` — pagination metadata
- `totalCount` — total number of matching items. Not all connection types support `totalCount` — if the query returns a validation error for this field, remove it and rely on `pageInfo` for pagination control

### Error Response

```json
{
  "errors": [
    {
      "message": "description of what went wrong",
      "path": ["evidence", "searchEvidence"],
      "extensions": {
        "code": "GRAPHQL_VALIDATION_FAILED"
      }
    }
  ]
}
```

Errors and data can coexist — partial results may be returned alongside errors for other fields.


## Experimental and Deprecated Fields

- `@experimental` — new features that may have breaking changes. Use with caution.
- `@deprecated` — features that will be removed. Migrate to the replacement.

Check for these directives when exploring the schema via `GET /onemodel/api/v1/supergraph/schema`.
