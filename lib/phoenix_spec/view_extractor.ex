defmodule PhoenixSpec.ViewExtractor do
  @moduledoc """
  Extracts response shapes from Phoenix JSON view modules by analyzing their AST.

  Detects:
  - Map literals returned by `data/1` and action functions
  - Ecto schema pattern matches to resolve field types
  - Calls to other `*JSON.data/1` for nested schemas
  - Wrapping patterns like `%{data: ...}`
  """

  alias PhoenixSpec.SchemaResolver

  defmodule Field do
    @moduledoc false
    defstruct [:name, :source_field, :type, :schema, :ref, :required, :items_ref]

    @type t :: %__MODULE__{
            name: atom(),
            source_field: atom() | nil,
            type: map() | nil,
            schema: module() | nil,
            ref: String.t() | nil,
            required: boolean(),
            items_ref: String.t() | nil
          }
  end

  defmodule ViewInfo do
    @moduledoc false
    defstruct [:module, :schema, :fields, :actions]

    @type t :: %__MODULE__{
            module: module(),
            schema: module() | nil,
            fields: [Field.t()],
            actions: %{atom() => action_info()}
          }

    @type action_info :: %{
            wrapper_key: atom() | nil,
            list: boolean(),
            ref: String.t() | nil
          }
  end

  @doc """
  Extracts view information from a JSON view module's source file.
  """
  @spec extract(module()) :: ViewInfo.t() | nil
  def extract(module) do
    with {:ok, source_path} <- source_path(module),
         {:ok, source} <- File.read(source_path),
         {:ok, ast} <- Code.string_to_quoted(source) do
      extract_from_ast(module, ast)
    else
      _ -> nil
    end
  end

  defp source_path(module) do
    case module.module_info(:compile)[:source] do
      nil -> :error
      source -> {:ok, List.to_string(source)}
    end
  end

  defp extract_from_ast(module, ast) do
    # A source file may contain multiple defmodule blocks.
    # Find the one matching our target module.
    module_ast = find_module_ast(ast, module)
    aliases = collect_aliases(module_ast || ast)
    functions = collect_functions(module_ast || ast)
    {schema, fields} = extract_data_function(functions, aliases)
    actions = extract_actions(functions)

    %ViewInfo{
      module: module,
      schema: schema,
      fields: fields,
      actions: actions
    }
  end

  defp find_module_ast(ast, target_module) do
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

  defp collect_aliases(ast) do
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

  defp collect_functions(ast) do
    {_, functions} =
      Macro.prewalk(ast, [], fn
        {:def, _meta, [{name, _, args}, body]} = node, acc when is_atom(name) ->
          {node, [{:def, name, args, body} | acc]}

        {:defp, _meta, [{name, _, args}, body]} = node, acc when is_atom(name) ->
          {node, [{:defp, name, args, body} | acc]}

        node, acc ->
          {node, acc}
      end)

    Enum.reverse(functions)
  end

  @doc false
  def extract_data_function(functions, aliases) do
    data_fn =
      Enum.find(functions, fn
        {:defp, :data, _, _} -> true
        {:def, :data, _, _} -> true
        _ -> false
      end)

    case data_fn do
      {_, :data, args, body} ->
        schema = extract_schema_from_args(args, aliases)
        fields = extract_fields_from_body(body, schema, aliases)
        {schema, fields}

      nil ->
        {nil, []}
    end
  end

  defp extract_schema_from_args(nil, _aliases), do: nil
  defp extract_schema_from_args([], _aliases), do: nil

  defp extract_schema_from_args(args, aliases) do
    Enum.find_value(args, fn
      {:=, _, [{:%, _, [schema_alias, _]}, _]} -> resolve_alias(schema_alias, aliases)
      {:=, _, [_, {:%, _, [schema_alias, _]}]} -> resolve_alias(schema_alias, aliases)
      {:%, _, [schema_alias, _]} -> resolve_alias(schema_alias, aliases)
      _ -> nil
    end)
  end

  defp resolve_alias({:__aliases__, _, [single]}, aliases) when is_atom(single) do
    Map.get(aliases, single, single)
  end

  defp resolve_alias({:__aliases__, _, parts}, _aliases) do
    Module.concat(parts)
  end

  defp resolve_alias(_, _aliases), do: nil

  defp extract_fields_from_body([do: body], schema, aliases) do
    extract_fields_from_body(body, schema, aliases)
  end

  defp extract_fields_from_body({:%{}, _, pairs}, schema, aliases) do
    Enum.map(pairs, fn {key, value} ->
      build_field(key, value, schema, aliases)
    end)
  end

  defp extract_fields_from_body({:__block__, _, exprs}, schema, aliases) do
    Enum.find_value(exprs, [], fn
      {:%{}, _, pairs} ->
        Enum.map(pairs, fn {key, value} -> build_field(key, value, schema, aliases) end)

      _ ->
        nil
    end)
  end

  defp extract_fields_from_body(_, _schema, _aliases), do: []

  defp build_field(key, value, schema, aliases) do
    case classify_value(value, schema, aliases) do
      {:schema_field, source_field, type} ->
        %Field{name: key, source_field: source_field, type: type, schema: schema, required: true}

      {:ref, ref_name} ->
        %Field{name: key, ref: ref_name, required: true}

      {:list_ref, ref_name} ->
        %Field{
          name: key,
          type: %{type: "array"},
          items_ref: ref_name,
          required: true
        }

      :unknown ->
        %Field{name: key, type: %{}, required: true}
    end
  end

  defp classify_value({{:., _, [Access, :get]}, _, _}, _schema, _aliases), do: :unknown

  # Detect `post.field` access
  defp classify_value({{:., _, [{var, _, _}, field]}, _, []}, schema, _aliases)
       when is_atom(field) and is_atom(var) do
    type = resolve_field_type(schema, field)
    {:schema_field, field, type}
  end

  # Detect calls like `TestAppWeb.UserJSON.data(post.author)` — full module path in AST
  defp classify_value(
         {{:., _, [{:__aliases__, _, json_module_parts}, :data]}, _, [_arg]},
         _schema,
         aliases
       ) do
    json_module = resolve_module(json_module_parts, aliases)
    ref_name = view_module_to_schema_name(json_module)
    {:ref, ref_name}
  end

  # Detect `for(item <- items, do: data(item))`
  defp classify_value({:for, _, [{:<-, _, [_, _]}, [do: inner]]}, _schema, aliases) do
    case inner do
      {:data, _, _} ->
        :unknown

      {{:., _, [{:__aliases__, _, parts}, :data]}, _, _} ->
        json_module = resolve_module(parts, aliases)
        ref_name = view_module_to_schema_name(json_module)
        {:list_ref, ref_name}

      _ ->
        :unknown
    end
  end

  defp classify_value(_, _schema, _aliases), do: :unknown

  defp resolve_module([single], aliases) when is_atom(single) do
    Map.get(aliases, single, single)
  end

  defp resolve_module(parts, _aliases), do: Module.concat(parts)

  defp resolve_field_type(nil, _field), do: %{}

  defp resolve_field_type(schema, field) do
    if SchemaResolver.ecto_schema?(schema) do
      case schema.__schema__(:type, field) do
        nil ->
          case SchemaResolver.association(schema, field) do
            nil -> %{}
            _assoc -> %{}
          end

        type ->
          PhoenixSpec.TypeMapping.to_openapi(type)
      end
    else
      %{}
    end
  end

  defp extract_actions(functions) do
    functions
    |> Enum.filter(fn
      {:def, name, _, _} when name in [:index, :show, :create, :update, :delete] -> true
      _ -> false
    end)
    |> Map.new(fn {:def, name, _args, body} ->
      {name, analyze_action_body(body)}
    end)
  end

  defp analyze_action_body([do: body]), do: analyze_action_body(body)

  defp analyze_action_body({:%{}, _, pairs}) do
    case pairs do
      [{wrapper_key, inner}] ->
        %{
          wrapper_key: wrapper_key,
          list: list_expression?(inner),
          ref: nil
        }

      _ ->
        %{wrapper_key: nil, list: false, ref: nil}
    end
  end

  defp analyze_action_body(_), do: %{wrapper_key: nil, list: false, ref: nil}

  defp list_expression?({:for, _, _}), do: true
  defp list_expression?(_), do: false

  @doc """
  Derives an OpenAPI schema name from a JSON view module name.

  ## Examples

      iex> PhoenixSpec.ViewExtractor.view_module_to_schema_name(TestAppWeb.PostJSON)
      "Post"

      iex> PhoenixSpec.ViewExtractor.view_module_to_schema_name(TestAppWeb.UserJSON)
      "User"
  """
  @spec view_module_to_schema_name(module()) :: String.t()
  def view_module_to_schema_name(module) do
    parts = Module.split(module)

    parts
    |> remove_web_prefix()
    |> Enum.join(".")
    |> String.replace_suffix("JSON", "")
  end

  defp remove_web_prefix([first | rest]) do
    case String.replace_suffix(first, "Web", "") do
      ^first -> [first | rest]
      _ -> rest
    end
  end
end
