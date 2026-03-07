defmodule Mix.Tasks.PhoenixSpec.Gen do
  @moduledoc """
  Generates an OpenAPI 3.1 specification from your Phoenix application.

  ## Usage

      mix phoenix_spec.gen

  ## Options

    * `--router` - Router module (default: auto-detected `*Web.Router`)
    * `--output` - Output file path (default: `priv/static/openapi.json`)
    * `--title` - API title (default: app name)
    * `--version` - API version (default: `"1.0.0"`)
    * `--format` - Output format: `json` or `yaml` (default: `json`)

  """

  use Mix.Task

  @shortdoc "Generates OpenAPI spec from Phoenix JSON views"

  @switches [
    router: :string,
    output: :string,
    title: :string,
    version: :string,
    format: :string
  ]

  @impl Mix.Task
  def run(args) do
    Mix.Task.run("compile")
    Mix.Task.run("app.start")

    {opts, _, _} = OptionParser.parse(args, switches: @switches)

    router = resolve_router(opts)
    format = Keyword.get(opts, :format, "json")
    output = Keyword.get(opts, :output, default_output(format))
    title = Keyword.get(opts, :title, default_title())
    version = Keyword.get(opts, :version, "1.0.0")

    Mix.shell().info("Generating OpenAPI spec from #{inspect(router)}...")

    spec =
      PhoenixSpec.OpenAPI.generate(
        router: router,
        title: title,
        version: version
      )

    content = encode(spec, format)

    File.mkdir_p!(Path.dirname(output))
    File.write!(output, content)

    schema_count = map_size(spec.components.schemas)
    path_count = map_size(spec.paths)

    Mix.shell().info("Generated #{output} (#{schema_count} schemas, #{path_count} paths)")
  end

  defp resolve_router(opts) do
    case Keyword.get(opts, :router) do
      nil -> detect_router()
      router_string -> Module.concat([router_string])
    end
  end

  defp detect_router do
    app = Mix.Project.config()[:app]
    web_module = app |> Atom.to_string() |> Macro.camelize()
    router = Module.concat(["#{web_module}Web", "Router"])

    if Code.ensure_loaded?(router) do
      router
    else
      Mix.raise("""
      Could not detect router module. Tried #{inspect(router)}.

      Please specify it explicitly:

          mix phoenix_spec.gen --router MyAppWeb.Router
      """)
    end
  end

  defp default_title do
    Mix.Project.config()[:app] |> Atom.to_string() |> Macro.camelize()
  end

  defp default_output("yaml"), do: "priv/static/openapi.yaml"
  defp default_output(_), do: "priv/static/openapi.json"

  defp encode(spec, "yaml") do
    if Code.ensure_loaded?(YamlElixir) do
      # yaml_elixir only reads YAML; for writing we do a simple conversion
      spec |> Jason.encode!() |> Jason.decode!() |> yaml_encode()
    else
      Mix.raise("Add {:yaml_elixir, \"~> 2.9\"} to your deps for YAML output")
    end
  end

  defp encode(spec, _json) do
    PhoenixSpec.OpenAPI.to_json(spec)
  end

  defp yaml_encode(data), do: to_yaml(data, 0)

  defp to_yaml(map, indent) when is_map(map) do
    map
    |> Enum.map(fn {key, value} ->
      prefix = String.duplicate("  ", indent)

      case value do
        v when is_map(v) and map_size(v) > 0 ->
          "#{prefix}#{key}:\n#{to_yaml(v, indent + 1)}"

        v when is_list(v) ->
          items = Enum.map_join(v, "\n", &"#{prefix}  - #{to_yaml_inline(&1)}")
          "#{prefix}#{key}:\n#{items}"

        _ ->
          "#{prefix}#{key}: #{to_yaml_value(value)}"
      end
    end)
    |> Enum.join("\n")
  end

  defp to_yaml_value(nil), do: "null"
  defp to_yaml_value(true), do: "true"
  defp to_yaml_value(false), do: "false"
  defp to_yaml_value(v) when is_binary(v), do: inspect(v)
  defp to_yaml_value(v), do: "#{v}"

  defp to_yaml_inline(v) when is_binary(v), do: inspect(v)
  defp to_yaml_inline(v), do: "#{v}"
end
