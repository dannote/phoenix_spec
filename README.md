# PhoenixSpec

[![Hex.pm](https://img.shields.io/hexpm/v/phoenix_spec.svg)](https://hex.pm/packages/phoenix_spec)
[![CI](https://github.com/dannote/phoenix_spec/actions/workflows/ci.yml/badge.svg)](https://github.com/dannote/phoenix_spec/actions)

Automatically generate [OpenAPI 3.1](https://spec.openapis.org/oas/v3.1.0) specifications from your Phoenix JSON views and Ecto schemas. No DSL to learn, no schemas to duplicate.

## How It Works

PhoenixSpec combines three sources already present in every Phoenix API:

1. **Ecto schemas** — field types (`:string`, `:integer`, `:utc_datetime`, …)
2. **JSON views** (`*JSON` modules) — which fields are exposed and how they nest
3. **Router** — routes, HTTP verbs, path parameters

```
Ecto schemas ──┐
               ├──▶ OpenAPI 3.1 spec
JSON views ────┘         │
                         ├──▶ openapi.json / openapi.yaml
Router ─────────────────▶│
                         └──▶ api.d.ts (optional)
```

## Quick Start

Add to your `mix.exs`:

```elixir
def deps do
  [
    {:phoenix_spec, "~> 0.1", only: :dev, runtime: false}
  ]
end
```

Generate the spec:

```
mix phoenix_spec.gen
```

That's it. The task introspects your router, finds the JSON views, reads the Ecto schemas, and writes `priv/static/openapi.json`.

## What Gets Inferred

Given a standard Phoenix JSON view:

```elixir
defmodule MyAppWeb.PostJSON do
  alias MyApp.Blog.Post

  def index(%{posts: posts}) do
    %{data: for(post <- posts, do: data(post))}
  end

  def show(%{post: post}) do
    %{data: data(post)}
  end

  def data(%Post{} = post) do
    %{
      id: post.id,
      title: post.title,
      published_at: post.published_at,
      author: MyAppWeb.UserJSON.data(post.author)
    }
  end
end
```

PhoenixSpec generates:

```json
{
  "components": {
    "schemas": {
      "Post": {
        "type": "object",
        "required": ["author", "id", "published_at", "title"],
        "properties": {
          "id": { "type": "integer" },
          "title": { "type": "string" },
          "published_at": { "type": "string", "format": "date-time" },
          "author": { "$ref": "#/components/schemas/User" }
        }
      }
    }
  }
}
```

### Automatically detected

| Pattern | Inferred as |
|---|---|
| `post.title` where `title` is `:string` in Ecto | `{type: "string"}` |
| `post.id` (primary key) | `{type: "integer"}` |
| `post.published_at` (`:utc_datetime`) | `{type: "string", format: "date-time"}` |
| `MyAppWeb.UserJSON.data(post.author)` | `$ref` to User schema |
| `for(c <- comments, do: CommentJSON.data(c))` | array of `$ref` |
| `%{data: for(...)}` in `index/1` | wrapped array response |
| `%{data: data(post)}` in `show/1` | wrapped object response |
| Route `get "/posts/:id"` | path parameter `{id}` |

### Ecto type mapping

| Ecto | OpenAPI |
|---|---|
| `:string` | `string` |
| `:integer` | `integer` |
| `:float` | `number` (double) |
| `:boolean` | `boolean` |
| `:decimal` | `string` (decimal) |
| `:id` | `integer` |
| `:binary_id` | `string` (uuid) |
| `:date` | `string` (date) |
| `:utc_datetime` / `:naive_datetime` | `string` (date-time) |
| `:map` | `object` |
| `{:array, :string}` | `array` of `string` |
| `Ecto.Enum` | `string` with `enum` values |

## Options

```
mix phoenix_spec.gen \
  --router MyAppWeb.Router \
  --output priv/static/openapi.json \
  --title "My API" \
  --version 2.0.0 \
  --format json
```

| Flag | Default | Description |
|---|---|---|
| `--router` | Auto-detected | Router module |
| `--output` | `priv/static/openapi.json` | Output file path |
| `--title` | App name | API title in the spec |
| `--version` | `1.0.0` | API version |
| `--format` | `json` | `json` or `yaml` |

## Roadmap

- [x] Ecto schema type inference
- [x] JSON view AST extraction
- [x] Nested view / `$ref` detection
- [x] Router → OpenAPI paths
- [x] Mix task
- [ ] Conditional / optional field detection
- [ ] `@spec` annotation support for computed fields
- [ ] Ecto.Enum value extraction
- [ ] Request body schemas from controller params
- [ ] Mix compiler integration (auto-regenerate)
- [ ] TypeScript `.d.ts` output

## License

MIT
