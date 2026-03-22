# OneModel GraphQL Query Examples

**Important:** These are illustrative query patterns, not guaranteed templates.
The OneModel schema is a federated supergraph that varies per server based on products, entitlements, and license. **Always fetch the actual schema** from `GET /onemodel/api/v1/supergraph/schema` and verify that the domains, types, fields, and arguments used below exist on the specific server before running any query. Replace placeholder values (in angle brackets) with actual values.

## Applications Domain

The applications domain uses the `applications` namespace to query applications, their versions, and bound package versions.

### List All Applications

```graphql
query {
  applications {
    searchApplications(where: {}, first: 50) {
      totalCount
      edges {
        node {
          key
          displayName
          description
          projectKey
          criticality
          maturityLevel
        }
      }
      pageInfo {
        hasNextPage
        endCursor
      }
    }
  }
}
```

### Get a Single Application by Key

```graphql
query {
  applications {
    getApplication(key: "<app-key>") {
      key
      displayName
      description
      projectKey
      criticality
      maturityLevel
      owners {
        name
        type
      }
      labels {
        key
        value
      }
    }
  }
}
```

### Search Applications with Filters

Filter by project, name substring, criticality, or maturity level:

```graphql
query {
  applications {
    searchApplications(
      where: {
        projectKey: "<project-key>"
        criticality: "high"
        maturityLevel: "production"
      }
      first: 25
      orderBy: { field: NAME, direction: ASC }
    ) {
      totalCount
      edges {
        node {
          key
          displayName
          criticality
          maturityLevel
        }
      }
    }
  }
}
```

### Get Application Versions

```graphql
query {
  applications {
    getApplication(key: "<app-key>") {
      displayName
      versionsConnection(first: 20) {
        totalCount
        edges {
          node {
            version
            status
          }
        }
        pageInfo {
          hasNextPage
          endCursor
        }
      }
    }
  }
}
```

### Get Application with Bound Package Versions

```graphql
query {
  applications {
    getApplication(key: "<app-key>") {
      displayName
      packageVersionsConnection(first: 25) {
        edges {
          node {
            type
            name
            version
          }
        }
      }
    }
  }
}
```


## Stored Packages Domain

The stored packages domain uses the `storedPackages` namespace to query packages and versions stored in your Artifactory repositories.

### Search Stored Packages

```graphql
query {
  storedPackages {
    searchPackages(
      where: { type: "docker" }
      first: 20
    ) {
      totalCount
      edges {
        node {
          name
          type
          description
          tags {
            key
            value
          }
        }
      }
      pageInfo {
        hasNextPage
        endCursor
      }
    }
  }
}
```

### Get a Stored Package by Name

```graphql
query {
  storedPackages {
    getPackage(name: "<package-name>", type: "<PACKAGE_TYPE>") {
      name
      type
      description
      versionsConnection(first: 10) {
        totalCount
        edges {
          node {
            version
            repos
          }
        }
      }
    }
  }
}
```

### Search Stored Package Versions

```graphql
query {
  storedPackages {
    searchPackageVersions(
      where: { type: "npm", name: "<package-name>" }
      first: 20
    ) {
      totalCount
      edges {
        node {
          version
          repos
        }
      }
      pageInfo {
        hasNextPage
        endCursor
      }
    }
  }
}
```


## Public Packages Domain

The public packages domain uses the `publicPackages` namespace to query packages from public registries (npm, Maven Central, PyPI, etc.).

### Search Public Packages

```graphql
query {
  publicPackages {
    searchPackages(
      where: { type: "npm", nameContains: "<search-term>" }
      first: 20
    ) {
      totalCount
      edges {
        node {
          name
          type
          description
          latestVersion
        }
      }
      pageInfo {
        hasNextPage
        endCursor
      }
    }
  }
}
```

### Get a Public Package

```graphql
query {
  publicPackages {
    getPackage(type: "maven", name: "<package-name>") {
      name
      type
      description
      latestVersion
      versionsConnection(first: 10) {
        edges {
          node {
            version
          }
        }
      }
    }
  }
}
```


## Release Lifecycle Management Domain

The release lifecycle domain uses the `releaseBundleVersion` namespace to query release bundle versions and their contents.

### Get Release Bundle Version Basic Info

```graphql
query {
  releaseBundleVersion {
    getVersion(name: "<bundle-name>", version: "<version>") {
      createdBy
      createdAt
    }
  }
}
```

Optional arguments for `getVersion`:
- `repositoryKey` — defaults to `release-bundles-v2`
- `projectKey` — scopes to a specific project

### Get Release Bundle Artifacts

```graphql
query {
  releaseBundleVersion {
    getVersion(name: "<bundle-name>", version: "<version>") {
      artifactsConnection(first: 50) {
        totalCount
        edges {
          node {
            name
            path
            sha256
            packageType
            packageName
            packageVersion
            size
            sourceRepositoryPath
            properties {
              key
              values
            }
          }
        }
        pageInfo {
          hasNextPage
          endCursor
        }
      }
    }
  }
}
```

### Get Release Bundle Source Builds

```graphql
query {
  releaseBundleVersion {
    getVersion(name: "<bundle-name>", version: "<version>") {
      fromBuilds {
        name
        number
        startedAt
        repositoryKey
      }
    }
  }
}
```

### Get Release Bundle with Artifact Evidence

```graphql
query {
  releaseBundleVersion {
    getVersion(name: "<bundle-name>", version: "<version>") {
      artifactsConnection(first: 50, where: { hasEvidence: true }) {
        edges {
          node {
            name
            packageType
            evidenceConnection(first: 5) {
              edges {
                node {
                  evidenceType
                  sha256
                }
              }
            }
          }
        }
      }
    }
  }
}
```

### Full Traceability — Release to Build Evidence

```graphql
query {
  releaseBundleVersion {
    getVersion(name: "<bundle-name>", version: "<version>") {
      createdBy
      createdAt
      fromBuilds {
        name
        number
        startedAt
        evidenceConnection(first: 10) {
          edges {
            node {
              evidenceType
              sha256
              issuedBy
              issuedAt
            }
          }
        }
      }
    }
  }
}
```


## Evidence Domain

The evidence domain uses the `evidence` namespace to search for evidence attached to artifacts in repositories.

### Search Evidence in a Repository

```graphql
query {
  evidence {
    searchEvidence(
      first: 10
      where: {
        hasSubjectWith: {
          repositoryKey: "<repo-key>"
        }
      }
    ) {
      totalCount
      edges {
        node {
          predicateSlug
          predicateType
          predicate
          verified
          downloadPath
          subject {
            path
            name
          }
        }
      }
      pageInfo {
        hasNextPage
        endCursor
      }
    }
  }
}
```

### Search Evidence for a Specific Artifact

```graphql
query {
  evidence {
    searchEvidence(
      where: {
        hasSubjectWith: {
          repositoryKey: "<repo-key>"
          path: "<path/to>"
          name: "<filename>"
        }
      }
    ) {
      edges {
        node {
          predicateSlug
          predicateType
          verified
          downloadPath
        }
      }
    }
  }
}
```

### Get Evidence by ID

```graphql
query {
  evidence {
    getEvidence(
      repositoryKey: "<repo-key>"
      path: "<path/to>"
      name: "<filename>"
    ) {
      id
      verified
    }
  }
}
```

### Search Evidence with Variables

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

Variables:
```json
{
  "repoKey": "example-repo-local",
  "path": "path/to",
  "name": "file.ext"
}
```


## Cross-Domain Queries

OneModel's strength is combining data from multiple domains in a single query.

### Release Bundle Artifacts with Evidence

```graphql
query {
  releaseBundleVersion {
    getVersion(name: "<bundle-name>", version: "<version>") {
      createdBy
      createdAt
      artifactsConnection(first: 20) {
        edges {
          node {
            name
            path
            packageType
            evidenceConnection(first: 5) {
              edges {
                node {
                  predicateSlug
                  verified
                }
              }
            }
          }
        }
      }
    }
  }
}
```
