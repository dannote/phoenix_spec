defmodule PhoenixSpec.Compiler do
  @moduledoc """
  Mix compiler that automatically regenerates OpenAPI specs when source files change.

  ## Setup

  Add to your `mix.exs`:

      def project do
        [
          compilers: Mix.compilers() ++ [:phoenix_spec],
          # ...
        ]
      end

  ## Configuration

  Configure in `config/config.exs`:

      config :phoenix_spec,
        router: MyAppWeb.Router,
        output: "priv/static/openapi.json",
        format: "json",
        title: "My API",
        version: "1.0.0"

  Or with multiple outputs:

      config :phoenix_spec,
        router: MyAppWeb.Router,
        outputs: [
          {"priv/static/openapi.json", "json"},
          {"priv/static/api.d.ts", "ts"}
        ]

  """

  use Mix.Task.Compiler

  @manifest_path "phoenix_spec.manifest"

  @impl true
  def run(_argv) do
    config = Application.get_all_env(:phoenix_spec)
    router = Keyword.get(config, :router)

    unless router do
      {:noop, []}
    else
      if should_regenerate?(config) do
        regenerate(config, router)
      else
        {:noop, []}
      end
    end
  end

  @impl true
  def manifests, do: [manifest_path()]

  @impl true
  def clean do
    File.rm(manifest_path())
    :ok
  end

  defp should_regenerate?(config) do
    manifest = read_manifest()
    source_files = source_files(config)
    current_hash = hash_files(source_files)
    current_hash != manifest[:hash]
  end

  defp regenerate(config, router) do
    title = Keyword.get(config, :title, default_title())
    version = Keyword.get(config, :version, "1.0.0")
    outputs = resolve_outputs(config)

    Enum.each(outputs, fn {output, format} ->
      case format do
        "ts" ->
          content = PhoenixSpec.TypeScript.generate(router: router)
          File.mkdir_p!(Path.dirname(output))
          File.write!(output, content)
          Mix.shell().info("[phoenix_spec] Generated #{output}")

        format ->
          spec =
            PhoenixSpec.OpenAPI.generate(
              router: router,
              title: title,
              version: version
            )

          content =
            case format do
              "yaml" -> PhoenixSpec.OpenAPI.to_yaml(spec)
              _ -> PhoenixSpec.OpenAPI.to_json(spec)
            end

          File.mkdir_p!(Path.dirname(output))
          File.write!(output, content)
          Mix.shell().info("[phoenix_spec] Generated #{output}")
      end
    end)

    source_files = source_files(config)
    write_manifest(%{hash: hash_files(source_files)})
    {:ok, []}
  end

  defp resolve_outputs(config) do
    case Keyword.get(config, :outputs) do
      nil ->
        format = Keyword.get(config, :format, "json")

        output =
          Keyword.get(config, :output, default_output(format))

        [{output, format}]

      outputs ->
        outputs
    end
  end

  defp source_files(config) do
    router = Keyword.get(config, :router)

    if router && Code.ensure_loaded?(router) do
      controllers =
        router.__routes__()
        |> Enum.map(& &1.plug)
        |> Enum.uniq()

      view_modules = PhoenixSpec.Discovery.json_views_from_router(router)

      (controllers ++ view_modules)
      |> Enum.flat_map(fn mod ->
        case mod.module_info(:compile)[:source] do
          nil -> []
          source -> [List.to_string(source)]
        end
      end)
      |> Enum.uniq()
    else
      []
    end
  end

  defp hash_files(files) do
    files
    |> Enum.sort()
    |> Enum.reduce(:crypto.hash_init(:sha256), fn file, hash ->
      case File.read(file) do
        {:ok, content} ->
          hash
          |> :crypto.hash_update(file)
          |> :crypto.hash_update(content)

        _ ->
          hash
      end
    end)
    |> :crypto.hash_final()
    |> Base.encode16(case: :lower)
  end

  defp manifest_path do
    Path.join(Mix.Project.manifest_path(), @manifest_path)
  end

  defp read_manifest do
    case File.read(manifest_path()) do
      {:ok, content} ->
        content |> :erlang.binary_to_term()

      _ ->
        %{}
    end
  rescue
    _ -> %{}
  end

  defp write_manifest(data) do
    File.mkdir_p!(Mix.Project.manifest_path())
    File.write!(manifest_path(), :erlang.term_to_binary(data))
  end

  defp default_title do
    Mix.Project.config()[:app] |> Atom.to_string() |> Macro.camelize()
  end

  defp default_output("yaml"), do: "priv/static/openapi.yaml"
  defp default_output("ts"), do: "priv/static/api.d.ts"
  defp default_output(_), do: "priv/static/openapi.json"
end
