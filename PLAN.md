# phoenix_spec

**Automatically generate OpenAPI 3.1 specifications from Phoenix JSON views and Ecto schemas.**

## Vision

Zero-annotation API spec generation for Phoenix. Define your Ecto schemas and JSON views as you normally would — `phoenix_spec` infers the types and generates a complete OpenAPI spec. No DSLs to learn, no schemas to duplicate.

## Name

`phoenix_spec` — available on hex.pm (verified 2026-03-07).

## Output Formats

1. **OpenAPI 3.1** (primary) — the universal interchange format, consumed by Swagger UI, Redoc, client generators, Postman, etc.
2. **TypeScript `.d.ts`** (optional convenience) — direct type generation for the 90% case of Phoenix backend + TypeScript frontend.

TypeSpec (Microsoft) was considered and rejected — it adds an unnecessary intermediate step when generating from code. OpenAPI is the universal hub.

## Architecture

```
┌──────────────┐     ┌──────────────────┐     ┌─────────────┐
│ Ecto Schemas │     │ Phoenix JSON      │     │ Router      │
│ (field types)│────▶│ Views (shape)     │────▶│ (routes)    │
└──────────────┘     └──────────────────┘     └─────────────┘
        │                     │                       │
        └─────────┬───────────┘                       │
                  ▼                                   ▼
         ┌────────────────┐                ┌──────────────────┐
         │ OpenAPI schemas │                │ OpenAPI paths    │
         └────────────────┘                └──────────────────┘
                  │                                   │
                  └───────────┬───────────────────────┘
                              ▼
                    ┌──────────────────┐
                    │ openapi.json     │
                    │ (or .yaml)       │
                    └──────────────────┘
                              │
                              ▼ (optional)
                    ┌──────────────────┐
                    │ api.d.ts         │
                    └──────────────────┘
```

## How It Works

### Source 1: Ecto Schemas (field types)

Ecto schemas already declare types for every field:

```elixir
schema "posts" do
  field :title, :string
  field :view_count, :integer
  field :published, :boolean
  field :published_at, :utc_datetime
  belongs_to :author, User
  has_many :comments, Comment
  timestamps()
end
```

Introspectable at compile time via `Post.__schema__(:fields)`, `Post.__schema__(:type, :title)`, `Post.__schema__(:associations)`, etc.

### Source 2: Phoenix JSON Views (response shape)

Phoenix 1.7+ JSON views define which fields are exposed and how:

```elixir
defmodule MyAppWeb.PostJSON do
  alias MyApp.Blog.Post

  def index(%{posts: posts}) do
    %{data: for(post <- posts, do: data(post))}
  end

  def show(%{post: post}) do
    %{data: data(post)}
  end

  defp data(%Post{} = post) do
    %{
      id: post.id,
      title: post.title,
      published_at: post.published_at,
      author: MyAppWeb.UserJSON.data(post.author)
    }
  end
end
```

We extract:
- **Which keys** are in the returned map literal
- **Which Ecto schema** via the `%Post{}` pattern match
- **Field types** by cross-referencing keys with `Post.__schema__(:type, field)`
- **Nested views** by detecting calls to other `*JSON.data/1` functions
- **Conditionals** → optional fields

### Source 3: Phoenix Router (routes)

`Phoenix.Router.routes/1` gives us all routes at runtime:

```elixir
[
  %{verb: :get, path: "/api/posts", plug: MyAppWeb.PostController, plug_opts: :index},
  %{verb: :get, path: "/api/posts/:id", plug: MyAppWeb.PostController, plug_opts: :show},
  ...
]
```

Cross-reference controller actions with JSON views to build OpenAPI paths.

### Type Mapping

| Ecto type | OpenAPI type |
|---|---|
| `:string` | `{type: "string"}` |
| `:integer` | `{type: "integer"}` |
| `:float` | `{type: "number", format: "double"}` |
| `:boolean` | `{type: "boolean"}` |
| `:id`, `:binary_id` | `{type: "integer"}` / `{type: "string", format: "uuid"}` |
| `:utc_datetime` | `{type: "string", format: "date-time"}` |
| `:date` | `{type: "string", format: "date"}` |
| `:map` | `{type: "object"}` |
| `:array` | `{type: "array"}` |
| `{:array, :string}` | `{type: "array", items: {type: "string"}}` |
| `Ecto.Enum` | `{type: "string", enum: [...values]}` |

### Annotations (progressive enhancement)

For computed/virtual fields that can't be inferred, use standard `@spec`:

```elixir
@spec data(Post.t()) :: %{
  id: integer(),
  title: String.t(),
  reading_time: integer()  # computed field, not in Ecto schema
}
defp data(%Post{} = post) do
  %{
    id: post.id,
    title: post.title,
    reading_time: div(String.length(post.body), 200)
  }
end
```

Or a lightweight module attribute for individual fields:

```elixir
@field_type reading_time: :integer
```

## Milestones

### v0.1 — Schema + View extraction → OpenAPI schemas

- [ ] Mix task `mix phoenix_spec.gen`
- [ ] Ecto schema introspection (fields, types, associations, enums)
- [ ] JSON view AST analysis (map literals, field access, pattern matches)
- [ ] Nested view detection (one view calling another)
- [ ] OpenAPI 3.1 schema output (components/schemas section)
- [ ] Basic type mapping (all Ecto types → OpenAPI)

### v0.2 — Routes → OpenAPI paths

- [ ] Phoenix Router introspection
- [ ] Controller → JSON view resolution
- [ ] OpenAPI paths generation
- [ ] Path parameters from route patterns
- [ ] Complete openapi.json output

### v0.3 — Polish & configurability

- [ ] YAML output option
- [ ] Conditional/optional field detection
- [ ] `@spec` annotation support for computed fields
- [ ] Configuration (output dir, base URL, API info, etc.)
- [ ] Mix compiler integration (auto-regenerate on change)

### v0.4 — TypeScript output

- [ ] TypeScript `.d.ts` generation from the same extracted info
- [ ] Interface generation for response types
- [ ] Enum → union type mapping

## Design Principles

1. **No new DSL** — works with standard Phoenix JSON views and Ecto schemas
2. **Zero config to start** — just add the dep and run the mix task
3. **Progressive enhancement** — add annotations only for what can't be inferred
4. **Idiomatic Elixir** — leverages compile-time introspection, not runtime reflection
5. **Composable** — JSON views already compose naturally; we follow that
