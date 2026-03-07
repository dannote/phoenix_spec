defmodule PhoenixSpec.ParamsExtractor do
  @moduledoc """
  Extracts request body schemas from Phoenix controller actions.

  Detects patterns like:
  - `params["key"]` or `params[:key]` access
  - `Map.get(params, "key")`
  - Pattern matching `%{"key" => value}` in function args
  - Changeset-based: `cast(struct, params, [:field1, :field2])`
  - Permit-style: extracting known keys from params
  """

  alias PhoenixSpec.{AstHelpers, SchemaResolver}

  defmodule ParamsInfo do
    @moduledoc false
    defstruct [:action, :schema, :fields]

    @type t :: %__MODULE__{
            action: atom(),
            schema: module() | nil,
            fields: [field_info()]
          }

    @type field_info :: %{name: atom() | String.t(), type: map()}
  end

  @doc """
  Extracts parameter info from a controller module's source.
  Returns a map of action names to their `ParamsInfo`.
  """
  @spec extract(module()) :: %{atom() => ParamsInfo.t()}
  def extract(controller) do
    case AstHelpers.parse_module_source(controller) do
      {:ok, _module, ast} -> extract_from_ast(controller, ast)
      :error -> %{}
    end
  end

  defp extract_from_ast(controller, ast) do
    module_ast = AstHelpers.find_module_ast(ast, controller)
    aliases = AstHelpers.collect_aliases(module_ast || ast)
    functions = collect_action_functions(module_ast || ast)

    Map.new(functions, fn {action, args, body} ->
      params_info = analyze_action(action, args, body, aliases)
      {action, params_info}
    end)
  end

  @action_names [:create, :update]

  defp collect_action_functions(ast) do
    {_, functions} =
      Macro.prewalk(ast, [], fn
        {:def, _, [{name, _, args}, body]} = node, acc when name in @action_names ->
          {node, [{name, args, body} | acc]}

        node, acc ->
          {node, acc}
      end)

    Enum.reverse(functions)
  end

  defp analyze_action(action, args, body, aliases) do
    param_keys = extract_param_keys_from_args(args) ++ extract_param_keys_from_body(body)
    {schema, cast_fields} = extract_changeset_info(body, aliases)

    fields =
      cond do
        cast_fields != [] -> resolve_fields_from_schema(schema, cast_fields)
        param_keys != [] -> Enum.uniq_by(param_keys, & &1.name)
        true -> []
      end

    %ParamsInfo{
      action: action,
      schema: schema,
      fields: fields
    }
  end

  # Pattern match on `%{"title" => title, "body" => body}` in action args
  defp extract_param_keys_from_args(nil), do: []

  defp extract_param_keys_from_args(args) do
    Enum.flat_map(args, fn
      {:%{}, _, pairs} ->
        Enum.flat_map(pairs, fn
          {key, _} when is_binary(key) -> [%{name: key, type: %{type: "string"}}]
          _ -> []
        end)

      _ ->
        []
    end)
  end

  # Look for changeset patterns:
  # - `cast(struct, params, [:field1, :field2])`
  # - `struct |> Ecto.Changeset.cast(params, [:field1, :field2])`
  # - `struct |> cast(params, [:field1, :field2])`
  defp extract_changeset_info([do: body], aliases),
    do: extract_changeset_info(body, aliases)

  defp extract_changeset_info(body, aliases) do
    {_, result} =
      Macro.prewalk(body, {nil, []}, fn
        # Direct call: cast(struct, params, fields)
        {:cast, _, [_struct, _params, fields]} = node, {schema, _} when is_list(fields) ->
          {node, {schema, extract_atom_fields(fields)}}

        # Piped: struct |> Ecto.Changeset.cast(params, fields)
        {{:., _, [{:__aliases__, _, _}, :cast]}, _, [_params, fields]} = node, {schema, _}
        when is_list(fields) ->
          {node, {schema, extract_atom_fields(fields)}}

        # Piped: struct |> cast(params, fields)
        {:cast, _, [_params, fields]} = node, {schema, _} when is_list(fields) ->
          {node, {schema, extract_atom_fields(fields)}}

        # Detect struct: `%Post{}`
        {:%, _, [{:__aliases__, _, parts}, _]} = node, {_, fields} ->
          {node, {resolve_module_parts(parts, aliases), fields}}

        node, acc ->
          {node, acc}
      end)

    result
  end

  defp extract_atom_fields(fields) do
    Enum.flat_map(fields, fn
      field when is_atom(field) -> [field]
      _ -> []
    end)
  end

  defp extract_param_keys_from_body([do: body]), do: extract_param_keys_from_body(body)

  defp extract_param_keys_from_body(body) do
    {_, keys} =
      Macro.prewalk(body, [], fn
        # params["key"]
        {{:., _, [Access, :get]}, _, [{:params, _, _}, key]} = node, acc
        when is_binary(key) ->
          {node, [%{name: key, type: %{type: "string"}} | acc]}

        # Map.get(params, "key")
        {{:., _, [{:__aliases__, _, [:Map]}, :get]}, _, [{:params, _, _}, key]} = node, acc
        when is_binary(key) ->
          {node, [%{name: key, type: %{type: "string"}} | acc]}

        node, acc ->
          {node, acc}
      end)

    Enum.reverse(keys)
  end

  defp resolve_fields_from_schema(schema, fields) do
    Enum.map(fields, fn field ->
      %{name: field, type: resolve_param_type(schema, field)}
    end)
  end

  defp resolve_param_type(schema, field) when not is_nil(schema) do
    if SchemaResolver.ecto_schema?(schema) do
      case schema.__schema__(:type, field) do
        nil -> %{type: "string"}
        ecto_type -> PhoenixSpec.TypeMapping.to_openapi(ecto_type)
      end
    else
      %{type: "string"}
    end
  end

  defp resolve_param_type(nil, _field), do: %{type: "string"}

  defp resolve_module_parts([single], aliases) when is_atom(single) do
    Map.get(aliases, single, single)
  end

  defp resolve_module_parts(parts, _aliases), do: Module.concat(parts)
end
