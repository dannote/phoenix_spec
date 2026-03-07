# Changelog

## Unreleased

- Ecto schema type inference (all types including Enum, arrays, embeds)
- JSON view AST extraction (field detection, nested views, `$ref` generation)
- Router introspection (paths, verbs, path parameters)
- OpenAPI 3.1 spec generation (JSON and YAML)
- TypeScript `.d.ts` output with correct types, optional `?`, enum unions, array syntax
- `mix phoenix_spec.gen` task
- Mix compiler for auto-regeneration on file changes
- Optional field detection via `@optional` and inline conditionals
- `@field_types` annotation for computed fields
- Embedded schemas (`embeds_one` → inline object, `embeds_many` → array)
- Request body schemas from controller and schema `changeset/2` cast fields
- Response status code inference from controller AST
- Operation summaries and unique operationIds
- Error responses (404, 422) by action type
- Association traversal (`comment.user.name`)
- Schema inference from aliases when no struct pattern match
- Inline map literal detection as object schemas
- Fallback extraction from private functions and action inline maps
- Non-controller route filtering (LiveView, OpenApiSpex, etc.)
- Polymorphic `oneOf` schemas from multiple `data/1` struct clauses
