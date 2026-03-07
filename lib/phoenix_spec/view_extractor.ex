defmodule PhoenixSpec.ViewExtractor do
  @moduledoc """
  Extracts response shapes from Phoenix JSON view modules by analyzing their AST.

  Detects:
  - Map literals returned by `data/1` and action functions
  - Ecto schema pattern matches to resolve field types
  - Calls to other `*JSON.data/1` for nested schemas
  - Wrapping patterns like `%{data: ...}`
  - Optional fields via `@optional` attribute or inline conditionals
  """

  alias PhoenixSpec.{AstHelpers, SchemaResolver}

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
    defstruct [:module, :schema, :fields, :actions, variants: []]

    @type variant :: %{schema: module() | nil, fields: [Field.t()]}

    @type t :: %__MODULE__{
            module: module(),
            schema: module() | nil,
            fields: [Field.t()],
            actions: %{atom() => action_info()},
            variants: [variant()]
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
  @spec extract(module()) :: struct() | nil
  def extract(module) do
    case AstHelpers.parse_module_source(module) do
      {:ok, _module, ast} -> extract_from_ast(module, ast)
      :error -> nil
    end
  end

  defp extract_from_ast(module, ast) do
    module_ast = AstHelpers.find_module_ast(ast, module)
    body = module_ast || ast
    aliases = AstHelpers.collect_aliases(body)
    functions = collect_functions(body)
    optional_fields = collect_optional_attr(body)
    spec_types = collect_spec_attr(body)

    {{schema, fields}, variants} =
      extract_data_function(functions, aliases, optional_fields, spec_types)

    actions = extract_actions(functions)

    %ViewInfo{
      module: module,
      schema: schema,
      fields: fields,
      actions: actions,
      variants: variants
    }
  end

  defp collect_optional_attr(ast) do
    {_, optional} =
      Macro.prewalk(ast, MapSet.new(), fn
        {:@, _, [{:optional, _, [fields]}]} = node, acc when is_list(fields) ->
          {node, Enum.reduce(fields, acc, &MapSet.put(&2, &1))}

        node, acc ->
          {node, acc}
      end)

    optional
  end

  defp collect_spec_attr(ast) do
    {_, specs} =
      Macro.prewalk(ast, %{}, fn
        {:@, _, [{:field_types, _, [fields]}]} = node, acc when is_list(fields) ->
          {node, Map.merge(acc, Map.new(fields))}

        node, acc ->
          {node, acc}
      end)

    specs
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
  def extract_data_function(
        functions,
        aliases,
        optional_fields \\ MapSet.new(),
        spec_types \\ %{}
      ) do
    data_fns =
      Enum.filter(functions, fn
        {:defp, :data, _, _} -> true
        {:def, :data, _, _} -> true
        _ -> false
      end)

    case data_fns do
      [] ->
        {result, []} =
          extract_from_alternative_function(functions, aliases, optional_fields, spec_types)

        {result, []}

      [single] ->
        {_, :data, args, body} = single

        schema =
          extract_schema_from_args(args, aliases) || infer_schema_from_aliases(aliases)

        fields = extract_fields_from_body(body, schema, aliases, optional_fields, spec_types)
        {{schema, fields}, []}

      multiple ->
        extract_polymorphic_data(multiple, aliases, optional_fields, spec_types)
    end
  end

  defp extract_polymorphic_data(data_fns, aliases, optional_fields, spec_types) do
    clause_data =
      Enum.map(data_fns, fn {_, :data, args, body} ->
        schema =
          extract_schema_from_args(args, aliases) || infer_schema_from_aliases(aliases)

        fields = extract_fields_from_body(body, schema, aliases, optional_fields, spec_types)
        {schema, fields}
      end)
      |> Enum.reject(fn {_schema, fields} -> fields == [] end)

    schemas = Enum.map(clause_data, fn {schema, _} -> schema end) |> Enum.uniq()

    if length(schemas) > 1 and Enum.all?(schemas, &(&1 != nil)) do
      {first_schema, first_fields} = hd(clause_data)
      variants = Enum.map(clause_data, fn {s, f} -> %{schema: s, fields: f} end)
      {{first_schema, first_fields}, variants}
    else
      {first_schema, first_fields} = hd(clause_data)
      {{first_schema, first_fields}, []}
    end
  end

  defp extract_from_alternative_function(functions, aliases, optional_fields, spec_types) do
    result =
      with nil <- extract_from_named_function(functions, aliases, optional_fields, spec_types),
           nil <- extract_from_action_inline(functions, aliases, optional_fields, spec_types) do
        {nil, []}
      end

    {result, []}
  end

  defp extract_from_named_function(functions, aliases, optional_fields, spec_types) do
    extraction_fn =
      functions
      |> Enum.find(fn
        {:defp, name, _, _} when name not in [:data] ->
          true

        _ ->
          false
      end)

    case extraction_fn do
      {_, _name, args, body} ->
        schema =
          extract_schema_from_args(args, aliases) || infer_schema_from_aliases(aliases)

        fields = extract_fields_from_body(body, schema, aliases, optional_fields, spec_types)

        if fields != [] do
          {schema, fields}
        end

      nil ->
        nil
    end
  end

  defp extract_from_action_inline(functions, aliases, optional_fields, spec_types) do
    action_fn =
      Enum.find(functions, fn
        {:def, name, _, _} when name in [:show, :create] -> true
        _ -> false
      end)

    with {:def, _, _, body} <- action_fn,
         {:%{}, _, pairs} <- unwrap_action_to_inner_map(body) do
      schema = infer_schema_from_aliases(aliases)

      fields =
        Enum.map(pairs, fn {key, value} ->
          build_field(key, value, schema, aliases, optional_fields, spec_types)
        end)

      if fields != [], do: {schema, fields}
    else
      _ -> nil
    end
  end

  defp unwrap_action_to_inner_map(do: body), do: unwrap_action_to_inner_map(body)

  defp unwrap_action_to_inner_map({:%{}, _, [{_wrapper_key, inner}]}) do
    case inner do
      {:%{}, _, _pairs} = map -> map
      _ -> nil
    end
  end

  defp unwrap_action_to_inner_map(_), do: nil

  defp infer_schema_from_aliases(aliases) do
    ecto_schemas =
      aliases
      |> Map.values()
      |> Enum.filter(&SchemaResolver.ecto_schema?/1)

    case ecto_schemas do
      [single] -> single
      _ -> nil
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

  defp extract_fields_from_body([do: body], schema, aliases, optional, spec_types) do
    extract_fields_from_body(body, schema, aliases, optional, spec_types)
  end

  defp extract_fields_from_body({:%{}, _, pairs}, schema, aliases, optional, spec_types) do
    Enum.map(pairs, fn {key, value} ->
      build_field(key, value, schema, aliases, optional, spec_types)
    end)
  end

  defp extract_fields_from_body({:__block__, _, exprs}, schema, aliases, optional, spec_types) do
    Enum.find_value(exprs, [], fn
      {:%{}, _, pairs} ->
        Enum.map(pairs, fn {key, value} ->
          build_field(key, value, schema, aliases, optional, spec_types)
        end)

      _ ->
        nil
    end)
  end

  defp extract_fields_from_body(_, _schema, _aliases, _optional, _spec_types), do: []

  defp build_field(key, value, schema, aliases, optional, spec_types) do
    explicitly_optional = MapSet.member?(optional, key)
    conditional = conditional_value?(value)
    required = not explicitly_optional and not conditional

    case classify_value(value, schema, aliases) do
      {:schema_field, source_field, type} ->
        %Field{
          name: key,
          source_field: source_field,
          type: type,
          schema: schema,
          required: required
        }

      {:ref, ref_name} ->
        %Field{name: key, ref: ref_name, required: required}

      {:list_ref, ref_name} ->
        %Field{name: key, type: %{type: "array"}, items_ref: ref_name, required: required}

      {:inline_object, properties} ->
        type = %{type: "object", properties: properties}
        %Field{name: key, type: type, required: required}

      :unknown ->
        type = resolve_spec_type(key, spec_types)
        %Field{name: key, type: type, required: required}
    end
  end

  defp resolve_spec_type(key, spec_types) do
    case Map.get(spec_types, key) do
      nil -> %{}
      ecto_type -> PhoenixSpec.TypeMapping.to_openapi(ecto_type)
    end
  end

  # Detect `if(cond, do: val, else: nil)` or `if cond do val else nil end`
  defp conditional_value?({:if, _, _}), do: true
  defp conditional_value?({:unless, _, _}), do: true
  defp conditional_value?({:case, _, _}), do: true
  defp conditional_value?({:&&, _, _}), do: true
  defp conditional_value?(_), do: false

  defp classify_value({{:., _, [Access, :get]}, _, _}, _schema, _aliases), do: :unknown

  # Detect `entity.assoc.field` — two-level access through an association
  defp classify_value(
         {{:., _, [{{:., _, [{_var, _, _}, assoc_name]}, _, []}, field]}, _, []},
         schema,
         _aliases
       )
       when is_atom(assoc_name) and is_atom(field) do
    type = resolve_association_field_type(schema, assoc_name, field)
    {:schema_field, field, type}
  end

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

  # Unwrap conditionals to classify the inner value
  defp classify_value({:if, _, [_cond, [do: inner, else: _]]}, schema, aliases) do
    classify_value(inner, schema, aliases)
  end

  defp classify_value({:if, _, [_cond, [do: inner]]}, schema, aliases) do
    classify_value(inner, schema, aliases)
  end

  # Detect inline map literals: `%{key1: expr1, key2: expr2}`
  defp classify_value({:%{}, _, pairs}, schema, aliases) when is_list(pairs) do
    properties =
      Map.new(pairs, fn {key, value} ->
        type =
          case classify_value(value, schema, aliases) do
            {:schema_field, _field, type} when type != %{} -> type
            _ -> %{}
          end

        {key, type}
      end)

    {:inline_object, properties}
  end

  defp classify_value(_, _schema, _aliases), do: :unknown

  defp resolve_module([single], aliases) when is_atom(single) do
    Map.get(aliases, single, single)
  end

  defp resolve_module(parts, _aliases), do: Module.concat(parts)

  defp resolve_field_type(nil, _field), do: %{}

  defp resolve_field_type(schema, field) do
    if SchemaResolver.ecto_schema?(schema) do
      resolve_ecto_field_type(schema, field)
    else
      %{}
    end
  end

  defp resolve_ecto_field_type(schema, field) do
    case schema.__schema__(:type, field) do
      nil -> %{}
      type -> PhoenixSpec.TypeMapping.to_openapi(type)
    end
  end

  defp resolve_association_field_type(nil, _assoc, _field), do: %{}

  defp resolve_association_field_type(schema, assoc_name, field) do
    if SchemaResolver.ecto_schema?(schema) do
      case SchemaResolver.association(schema, assoc_name) do
        %{related: related_schema} -> resolve_field_type(related_schema, field)
        _ -> %{}
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

  defp analyze_action_body(do: body), do: analyze_action_body(body)

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

  defp list_expression?({{:., _, [{:__aliases__, _, [:Enum]}, :map]}, _, _}), do: true

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
