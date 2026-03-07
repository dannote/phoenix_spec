defmodule PhoenixSpec.AstHelpers do
  @moduledoc false

  @spec find_module_ast(Macro.t(), module()) :: Macro.t() | nil
  def find_module_ast(ast, target_module) do
    target_parts = Module.split(target_module)

    {_, found} =
      Macro.prewalk(ast, nil, fn
        {:defmodule, _, [{:__aliases__, _, parts}, [do: body]]} = node, nil ->
          if Enum.map(parts, &Atom.to_string/1) == target_parts do
            {node, body}
          else
            {node, nil}
          end

        node, acc ->
          {node, acc}
      end)

    found
  end

  @spec collect_aliases(Macro.t()) :: %{atom() => module()}
  def collect_aliases(ast) do
    {_, aliases} =
      Macro.prewalk(ast, %{}, fn
        {:alias, _, [{:__aliases__, _, full_parts}]} = node, acc ->
          short = List.last(full_parts)
          {node, Map.put(acc, short, Module.concat(full_parts))}

        node, acc ->
          {node, acc}
      end)

    aliases
  end
end
