# GraphQL Playground

The JFrog Platform UI includes a built-in GraphQL Playground where users can interactively discover and explore OneModel capabilities — browse the schema, build queries with autocomplete, and test them in real time.

It is available at **Integrations > GraphQL Playground** in the Platform UI, or directly at:

```
$JFROG_URL/ui/onemodel/playground
```

Where `$JFROG_URL` is the platform URL resolved in step 1 of the workflow.

**When to suggest the playground to the user:**

- The user's request involves complex queries that are difficult to get right in a single conversation turn (e.g. deep nested filters across multiple domains)
- Multiple query attempts have failed and interactive exploration with autocomplete and inline schema docs would help the user move faster
- The user wants to explore what data or capabilities are available rather than run a specific query
- The user explicitly asks about a UI or visual tool for GraphQL, or asks "how can I explore this myself"

When suggesting the playground, include the direct URL using the resolved `$JFROG_URL` so the user can open it immediately.


## Official Documentation

- [JFrog OneModel GraphQL](https://jfrog.com/help/r/jfrog-rest-apis/jfrog-one-model-graphql)
- [OneModel Common Patterns](https://jfrog.com/help/r/jfrog-rest-apis/one-model-graphql-common-patterns-and-conventions)
- [Release Lifecycle GraphQL](https://jfrog.com/help/r/jfrog-rest-apis/get-release-bundle-v2-version-graphql-use-cases-examples)
- [GraphQL Introduction](https://graphql.org/learn/)
