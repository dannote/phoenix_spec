# Changelog

## v0.3.0

### New Features

- **`@field_types` annotation** — Annotate computed fields with Ecto types:
  `@field_types reading_time: :integer, full_name: :string`. Resolves fields that aren't
  backed by an Ecto schema column.

- **Embedded schemas** — `embeds_one` generates an inline object schema with all embedded
  fields. `embeds_many` generates an array of inline objects. Works in both OpenAPI and
  TypeScript output.

- **Response status code inference** — Detects `put_status(:created)` and
  `send_resp(conn, :no_content, "")` in controller source to generate correct response codes
  (201, 204, etc.). Falls back to sensible defaults: `create` → 201, `delete` → 204.

## v0.2.0

### New Features

- **Optional field detection** — Fields wrapped in `if`/`unless`/`case`/`&&` are automatically
  marked as not required in the OpenAPI output. Use `@optional [:field1, :field2]` in your JSON
  view for explicit control.

- **Request body schemas** — `create` and `update` controller actions are analyzed for
  `Ecto.Changeset.cast/3` calls. The cast field list and Ecto schema types are used to generate
  typed `requestBody` schemas in the OpenAPI output.

- **TypeScript `.d.ts` output** — `mix phoenix_spec.gen --format ts` generates TypeScript
  interfaces with correct types, optional fields (`?`), enum unions, and array syntax.

- **Mix compiler** — Add `:phoenix_spec` to your compilers list for automatic spec regeneration
  when source files change. Supports multiple output formats in one config.

- **Ecto.Enum support** — Enum fields are mapped to `{type: "string", enum: [...]}` with
  the actual declared values.

- **Array type support** — `{:array, :string}` and similar Ecto array types are correctly
  mapped to OpenAPI array schemas.

## v0.1.0

- Initial release
- Ecto schema type inference
- JSON view AST extraction (field detection, nested views, `$ref` generation)
- Router introspection (paths, verbs, path parameters)
- OpenAPI 3.1 spec generation (JSON and YAML)
- `mix phoenix_spec.gen` task
