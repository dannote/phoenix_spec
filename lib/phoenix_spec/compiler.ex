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

  Configure in `config/dev.exs`:

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

  alias PhoenixSpec.Output

  @manifest_path "phoenix_spec.manifest"

  @impl true
  def run(_argv) do
    config = Application.get_all_env(:phoenix_spec)
    router = Keyword.get(config, :router)

    if router && should_regenerate?(config) do
      regenerate(config, router)
    else
      {:noop, []}
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
    title = Keyword.get_lazy(config, :title, &Output.default_title/0)
    version = Keyword.get(config, :version, "1.0.0")
    outputs = resolve_outputs(config)

    Enum.each(outputs, fn {output, format} ->
      content = generate_content(format, router: router, title: title, version: version)
      write_output(output, content)
    end)

    source_files = source_files(config)
    write_manifest(%{hash: hash_files(source_files)})
    {:ok, []}
  end

  defp generate_content("ts", opts), do: PhoenixSpec.TypeScript.generate(opts)

  defp generate_content("yaml", opts),
    do: opts |> PhoenixSpec.OpenAPI.generate() |> PhoenixSpec.OpenAPI.to_yaml()

  defp generate_content(_, opts),
    do: opts |> PhoenixSpec.OpenAPI.generate() |> PhoenixSpec.OpenAPI.to_json()

  defp write_output(output, content) do
    File.mkdir_p!(Path.dirname(output))
    File.write!(output, content)
    Mix.shell().info("[phoenix_spec] Generated #{output}")
  end

  defp resolve_outputs(config) do
    case Keyword.get(config, :outputs) do
      nil ->
        format = Keyword.get(config, :format, "json")

        output =
          Keyword.get(config, :output, Output.default_path(format))

        [{output, format}]

      outputs ->
        outputs
    end
  end

  defp source_files(config) do
    source_paths =
      Keyword.get_lazy(config, :source_paths, fn ->
        Mix.Project.config()
        |> Keyword.get(:elixirc_paths, ["lib"])
      end)

    source_paths
    |> Enum.flat_map(&Path.wildcard(Path.join(&1, "**/*.{ex,exs}")))
    |> Kernel.++(Path.wildcard("config/**/*.{ex,exs}"))
    |> Kernel.++(["mix.exs"])
    |> Enum.filter(&File.regular?/1)
    |> Enum.uniq()
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
    with {:ok, content} <- File.read(manifest_path()),
         manifest when is_map(manifest) <- :erlang.binary_to_term(content, [:safe]) do
      manifest
    else
      _error -> %{}
    end
  rescue
    ArgumentError -> %{}
  end

  defp write_manifest(data) do
    File.mkdir_p!(Mix.Project.manifest_path())
    File.write!(manifest_path(), :erlang.term_to_binary(data))
  end
end
