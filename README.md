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
      status: post.status,
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
        "required": ["author", "id", "published_at", "status", "title"],
        "properties": {
          "id": { "type": "integer" },
          "title": { "type": "string" },
          "status": { "type": "string", "enum": ["draft", "published", "archived"] },
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
| `post.status` (`Ecto.Enum`) | `{type: "string", enum: [...]}` |
| `post.tags` (`{:array, :string}`) | `{type: "array", items: {type: "string"}}` |
| `cost.amount` (through `belongs_to :cost`) | resolved from associated schema |
| `MyAppWeb.UserJSON.data(post.author)` | `$ref` to User schema |
| `for(c <- comments, do: CommentJSON.data(c))` | array of `$ref` |
| `%{data: for(...)}` in `index/1` | wrapped array response |
| `%{data: data(post)}` in `show/1` | wrapped object response |
| `%{name: x, email: y}` inline map literal | inline `object` with typed properties |
| Route `get "/posts/:id"` | path parameter `{id}` |
| `user.address` (`embeds_one`) | inline object schema |
| `user.links` (`embeds_many`) | array of inline objects |
| `if(cond, do: val)` in map value | optional field |
| `Ecto.Changeset.cast(struct, params, [:f1, :f2])` | request body schema |
| `put_status(conn, :created)` | 201 response code |
| `send_resp(conn, :no_content, "")` | 204 response code |
| `create` action | 422 error response |
| `show` / `update` / `delete` action | 404 error response |
| Multiple `data/1` with different structs | `oneOf` schema |

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
| `embeds_one` | inline `object` with embedded schema fields |
| `embeds_many` | `array` of inline `object` |

## Optional Fields

Fields wrapped in `if`, `unless`, `case`, or `&&` in the JSON view map literal are automatically marked as optional (not included in `required`).

You can also explicitly list optional fields with `@optional`:

```elixir
defmodule MyAppWeb.UserJSON do
  @optional [:bio, :avatar_url]

  def data(%User{} = user) do
    %{
      id: user.id,
      name: user.name,
      bio: user.bio,
      avatar_url: user.avatar_url
    }
  end
end
```

## Field Type Annotations

Computed fields (not backed by an Ecto schema field) default to `unknown`. Annotate them with `@field_types`:

```elixir
defmodule MyAppWeb.PostJSON do
  @field_types reading_time: :integer, full_name: :string

  def data(%Post{} = post) do
    %{
      id: post.id,
      title: post.title,
      reading_time: div(String.length(post.body), 200),
      full_name: "#{post.author.first} #{post.author.last}"
    }
  end
end
```

Any Ecto type works: `:string`, `:integer`, `:boolean`, `:float`, `{:array, :string}`, etc.

## Embedded Schemas

`embeds_one` and `embeds_many` are rendered as inline object schemas:

```json
{
  "address": {
    "type": "object",
    "required": ["city", "street", "zip"],
    "properties": {
      "street": { "type": "string" },
      "city": { "type": "string" },
      "zip": { "type": "string" }
    }
  },
  "social_links": {
    "type": "array",
    "items": {
      "type": "object",
      "properties": {
        "platform": { "type": "string" },
        "url": { "type": "string" }
      }
    }
  }
}
```

## Response Status Codes

PhoenixSpec infers status codes from your controller source:

| Pattern | Status |
|---|---|
| `put_status(conn, :created)` | `201` |
| `send_resp(conn, :no_content, "")` | `204` |
| `create` action (default) | `201` |
| `delete` action (default) | `204` |
| Everything else | `200` |

Custom status codes set via `put_status` or `send_resp` in the controller body take precedence over defaults.

## Request Bodies

PhoenixSpec detects `Ecto.Changeset.cast/3` calls to build typed request body schemas. It handles two patterns:

**Direct cast in controller** (custom controllers):

```elixir
def create(conn, %{"post" => post_params}) do
  %Post{} |> Ecto.Changeset.cast(post_params, [:title, :body, :published])
end
```

**Delegation via context module** (standard `phx.gen.json` pattern):

```elixir
# Controller
def create(conn, %{"post" => post_params}) do
  with {:ok, %Post{} = post} <- Blog.create_post(post_params) do ...

# Schema — PhoenixSpec finds cast/3 here automatically
def changeset(post, attrs) do
  post |> cast(attrs, [:title, :body, :published]) |> validate_required([:title])
end
```

Both produce a properly nested request body:

```json
{
  "requestBody": {
    "content": {
      "application/json": {
        "schema": {
          "type": "object",
          "properties": {
            "post": {
              "type": "object",
              "properties": {
                "title": { "type": "string" },
                "body": { "type": "string" },
                "published": { "type": "boolean" }
              }
            }
          }
        }
      }
    }
  }
}
```

## Polymorphic Views

When `data/1` has multiple clauses matching different structs, PhoenixSpec generates a `oneOf` schema:

```elixir
defmodule MyAppWeb.MessageJSON do
  def data(%TextMessage{} = msg) do
    %{id: msg.id, type: "text", text: msg.text, sender: msg.sender}
  end

  def data(%ImageMessage{} = msg) do
    %{id: msg.id, type: "image", url: msg.url, width: msg.width, height: msg.height, sender: msg.sender}
  end
end
```

Generates:

```json
{
  "Message": {
    "oneOf": [
      {
        "type": "object",
        "properties": {
          "id": { "type": "integer" },
          "text": { "type": "string" },
          "sender": { "type": "string" }
        }
      },
      {
        "type": "object",
        "properties": {
          "id": { "type": "integer" },
          "url": { "type": "string" },
          "width": { "type": "integer" },
          "height": { "type": "integer" },
          "sender": { "type": "string" }
        }
      }
    ]
  }
}
```

In TypeScript, this becomes a union type:

```typescript
export interface MessageVariant1 { id: number; text: string; sender: string; }
export interface MessageVariant2 { id: number; url: string; width: number; height: number; sender: string; }
export type Message = MessageVariant1 | MessageVariant2;
```

## TypeScript Output

Generate TypeScript type definitions instead of (or alongside) OpenAPI:

```
mix phoenix_spec.gen --format ts --output priv/static/api.d.ts
```

Produces:

```typescript
// Generated by phoenix_spec — do not edit

export interface Post {
  id: number;
  title: string;
  status: ("draft" | "published" | "archived");
  published_at: string;
  author: User;
}

export interface User {
  id: number;
  name: string;
  email: string;
}
```

## Mix Compiler

Auto-regenerate on file changes by adding the compiler to your `mix.exs`:

```elixir
def project do
  [
    compilers: Mix.compilers() ++ [:phoenix_spec],
    # ...
  ]
end
```

Configure in `config/dev.exs`:

```elixir
config :phoenix_spec,
  router: MyAppWeb.Router,
  output: "priv/static/openapi.json",
  format: "json",
  title: "My API",
  version: "1.0.0"
```

Or generate multiple outputs at once:

```elixir
config :phoenix_spec,
  router: MyAppWeb.Router,
  outputs: [
    {"priv/static/openapi.json", "json"},
    {"priv/static/api.d.ts", "ts"}
  ]
```

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
| `--format` | `json` | `json`, `yaml`, or `ts` |

## Roadmap

- [x] Ecto schema type inference
- [x] JSON view AST extraction
- [x] Nested view / `$ref` detection
- [x] Router → OpenAPI paths
- [x] Mix task
- [x] Ecto.Enum value extraction
- [x] Conditional / optional field detection
- [x] Request body schemas from controller/schema changeset
- [x] TypeScript `.d.ts` output
- [x] Mix compiler integration (auto-regenerate)
- [x] `@field_types` annotation for computed fields
- [x] Embedded schemas (`embeds_one` / `embeds_many`)
- [x] Response status code inference from controller AST
- [x] Error response schemas (404, 422)
- [x] Association traversal (`post.author.name`)
- [x] Inline map literals as object schemas
- [x] Operation summaries and unique operationIds
- [x] Polymorphic views / `oneOf`

## License

MIT
