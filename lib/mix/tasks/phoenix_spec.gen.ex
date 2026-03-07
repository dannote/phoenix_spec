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
    * `--format` - Output format: `json`, `yaml`, or `ts` (default: `json`)

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

    case format do
      "ts" ->
        Mix.shell().info("Generating TypeScript definitions from #{inspect(router)}...")

        content = PhoenixSpec.TypeScript.generate(router: router)

        File.mkdir_p!(Path.dirname(output))
        File.write!(output, content)

        Mix.shell().info("Generated #{output}")

      _ ->
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
  defp default_output("ts"), do: "priv/static/api.d.ts"
  defp default_output(_), do: "priv/static/openapi.json"

  defp encode(spec, "yaml"), do: PhoenixSpec.OpenAPI.to_yaml(spec)
  defp encode(spec, _json), do: PhoenixSpec.OpenAPI.to_json(spec)
end
