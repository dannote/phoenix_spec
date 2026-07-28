defmodule PhoenixSpec.Output do
  @moduledoc """
  Shared defaults for generated PhoenixSpec output.
  """

  @spec default_title() :: String.t()
  def default_title do
    Mix.Project.config()
    |> Keyword.fetch!(:app)
    |> Atom.to_string()
    |> Macro.camelize()
  end

  @spec default_path(String.t()) :: String.t()
  def default_path("yaml"), do: "priv/static/openapi.yaml"
  def default_path("ts"), do: "priv/static/api.d.ts"
  def default_path(_format), do: "priv/static/openapi.json"
end
