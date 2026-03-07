defmodule PhoenixSpec.Discovery do
  @moduledoc """
  Discovers JSON view modules and their associated controllers in a Phoenix application.
  """

  @doc """
  Finds all `*JSON` view modules that are referenced by the given router's controllers.
  """
  @spec json_views_from_router(module()) :: [module()]
  def json_views_from_router(router) do
    router.__routes__()
    |> Enum.map(& &1.plug)
    |> Enum.uniq()
    |> Enum.filter(&controller?/1)
    |> Enum.flat_map(&controller_json_views/1)
    |> Enum.uniq()
  end

  defp controller?(module) do
    module |> Atom.to_string() |> String.ends_with?("Controller")
  end

  @doc """
  Returns the JSON view module for a controller, following Phoenix 1.7+ conventions.

  `MyAppWeb.PostController` → `MyAppWeb.PostJSON`
  """
  @spec controller_to_json_view(module()) :: module() | nil
  def controller_to_json_view(controller) do
    json_module =
      controller
      |> Atom.to_string()
      |> String.replace("Controller", "JSON")

    module = String.to_existing_atom(json_module)

    if Code.ensure_loaded?(module), do: module, else: nil
  rescue
    ArgumentError -> nil
  end

  defp controller_json_views(controller) do
    case controller_to_json_view(controller) do
      nil -> []
      module -> [module]
    end
  end
end
