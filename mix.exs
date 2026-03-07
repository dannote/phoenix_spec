defmodule PhoenixSpec.MixProject do
  use Mix.Project

  @version "0.1.0-dev"
  @source_url "https://github.com/dannote/phoenix_spec"

  def project do
    [
      app: :phoenix_spec,
      version: @version,
      elixir: "~> 1.17",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      package: package(),
      docs: docs(),
      name: "PhoenixSpec",
      description:
        "Automatically generate OpenAPI 3.1 specs from Phoenix JSON views and Ecto schemas",
      source_url: @source_url,
      elixirc_paths: elixirc_paths(Mix.env())
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      {:phoenix, "~> 1.7", optional: true},
      {:ecto, "~> 3.10", optional: true},
      {:jason, "~> 1.0"},
      {:yaml_elixir, "~> 2.9", optional: true},
      {:ex_doc, "~> 0.30", only: :dev, runtime: false}
    ]
  end

  defp package do
    [
      licenses: ["MIT"],
      links: %{"GitHub" => @source_url},
      files: ~w(lib mix.exs README.md LICENSE CHANGELOG.md)
    ]
  end

  defp docs do
    [
      main: "PhoenixSpec",
      source_url: @source_url,
      source_ref: "v#{@version}"
    ]
  end
end
