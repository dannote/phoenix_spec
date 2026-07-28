defmodule PhoenixSpec.Discovery do
  @moduledoc """
  Discovers response modules associated with controllers in a Phoenix application.
  """

  alias PhoenixSpec.AstHelpers

  @doc """
  Finds response modules for the given router's controllers.

  Phoenix `*JSON` modules are preferred. A controller is returned as its own
  response module when it renders JSON inline.
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
      |> String.replace_suffix("Controller", "JSON")

    module = String.to_existing_atom(json_module)

    if Code.ensure_loaded?(module), do: module, else: nil
  rescue
    ArgumentError -> nil
  end

  defp controller_json_views(controller) do
    case controller_to_json_view(controller) do
      nil -> if inline_json_controller?(controller), do: [controller], else: []
      module -> [module]
    end
  end

  defp inline_json_controller?(controller) do
    case AstHelpers.parse_module_source(controller) do
      {:ok, _module, ast} ->
        body = AstHelpers.find_module_ast(ast, controller) || ast

        {_, found?} =
          Macro.prewalk(body, false, fn
            {:json, _, _arguments} = node, _found? -> {node, true}
            {{:., _, [_module, :json]}, _, _arguments} = node, _found? -> {node, true}
            node, found? -> {node, found?}
          end)

        found?

      :error ->
        false
    end
  end
end
