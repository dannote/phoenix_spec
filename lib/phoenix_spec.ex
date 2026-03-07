defmodule PhoenixSpec do
  @moduledoc """
  Automatically generate OpenAPI 3.1 specs from Phoenix JSON views and Ecto schemas.

  ## Quick Start

  Add `phoenix_spec` to your dependencies, then run:

      mix phoenix_spec.gen

  This will introspect your Phoenix router, JSON views, and Ecto schemas
  to generate an `openapi.json` file.

  ## How It Works

  1. **Ecto schemas** provide field types (`:string`, `:integer`, etc.)
  2. **Phoenix JSON views** (`*JSON` modules) define response shapes
  3. **Phoenix Router** provides routes, verbs, and path parameters

  PhoenixSpec combines these three sources to produce a complete OpenAPI 3.1
  specification with zero annotations required for typical Ecto-backed fields.
  """
end
