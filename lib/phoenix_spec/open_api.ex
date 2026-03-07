defmodule PhoenixSpec.OpenAPI do
  @moduledoc """
  Generates an OpenAPI 3.1 specification from extracted view and schema information.
  """

  alias PhoenixSpec.{Discovery, ParamsExtractor, StatusExtractor, ViewExtractor}
  alias PhoenixSpec.ViewExtractor.{Field, ViewInfo}

  @doc """
  Builds a complete OpenAPI 3.1 document.
  """
  @spec generate(keyword()) :: map()
  def generate(opts \\ []) do
    router = Keyword.fetch!(opts, :router)
    title = Keyword.get(opts, :title, "API")
    version = Keyword.get(opts, :version, "1.0.0")
    description = Keyword.get(opts, :description, nil)

    json_views = Discovery.json_views_from_router(router)
    view_infos = Enum.map(json_views, &ViewExtractor.extract/1) |> Enum.reject(&is_nil/1)
    controllers = extract_controllers(router)
    params_map = extract_all_params(controllers)
    status_map = extract_all_statuses(controllers)
    schemas = build_schemas(view_infos)
    paths = build_paths(router, view_infos, params_map, status_map)

    spec = %{
      openapi: "3.1.0",
      info: build_info(title, version, description),
      paths: paths,
      components: %{schemas: schemas}
    }

    drop_nils(spec)
  end

  defp build_info(title, version, description) do
    %{title: title, version: version, description: description}
    |> drop_nils()
  end

  defp build_schemas(view_infos) do
    Map.new(view_infos, fn %ViewInfo{} = info ->
      name = ViewExtractor.view_module_to_schema_name(info.module)
      schema = fields_to_schema(info.fields)
      {name, schema}
    end)
  end

  defp fields_to_schema(fields) do
    properties =
      Map.new(fields, fn %Field{} = field ->
        {field.name, field_to_property(field)}
      end)

    required =
      fields
      |> Enum.filter(& &1.required)
      |> Enum.map(& &1.name)
      |> Enum.sort()

    result = %{type: "object", properties: properties}

    if required == [] do
      result
    else
      Map.put(result, :required, required)
    end
  end

  defp field_to_property(%Field{ref: ref}) when is_binary(ref) do
    %{"$ref": "#/components/schemas/#{ref}"}
  end

  defp field_to_property(%Field{items_ref: items_ref}) when is_binary(items_ref) do
    %{type: "array", items: %{"$ref": "#/components/schemas/#{items_ref}"}}
  end

  defp field_to_property(%Field{type: %{type: "embedded", cardinality: :one, schema: schema}}) do
    embedded_schema_to_openapi(schema)
  end

  defp field_to_property(%Field{type: %{type: "embedded", cardinality: :many, schema: schema}}) do
    %{type: "array", items: embedded_schema_to_openapi(schema)}
  end

  defp field_to_property(%Field{type: type}) when is_map(type) and map_size(type) > 0 do
    type
  end

  defp field_to_property(%Field{}) do
    %{}
  end

  defp embedded_schema_to_openapi(schema) do
    fields = schema.__schema__(:fields) -- [:id]

    properties =
      Map.new(fields, fn field ->
        type = schema.__schema__(:type, field)
        {field, PhoenixSpec.TypeMapping.to_openapi(type)}
      end)

    required = fields |> Enum.sort()

    %{type: "object", properties: properties, required: required}
  end

  defp extract_controllers(router) do
    router.__routes__()
    |> Enum.map(& &1.plug)
    |> Enum.uniq()
  end

  defp extract_all_params(controllers) do
    Map.new(controllers, fn controller ->
      {controller, ParamsExtractor.extract(controller)}
    end)
  end

  defp extract_all_statuses(controllers) do
    Map.new(controllers, fn controller ->
      {controller, StatusExtractor.extract(controller)}
    end)
  end

  defp build_paths(router, view_infos, params_map, status_map) do
    view_map = build_view_lookup(view_infos)

    router.__routes__()
    |> Enum.filter(&json_route?/1)
    |> Enum.group_by(& &1.path)
    |> Map.new(fn {path, routes} ->
      openapi_path = phoenix_path_to_openapi(path)
      operations = build_operations(routes, view_map, params_map, status_map)
      {openapi_path, operations}
    end)
  end

  defp build_view_lookup(view_infos) do
    Map.new(view_infos, fn %ViewInfo{module: module} = info ->
      {module, info}
    end)
  end

  defp json_route?(%{plug: plug}) do
    plug |> Atom.to_string() |> String.ends_with?("Controller")
  end

  defp build_operations(routes, view_map, params_map, status_map) do
    action_verbs = count_action_verbs(routes)

    Map.new(routes, fn route ->
      verb = route_verb(route)
      needs_verb_suffix = Map.get(action_verbs, route.plug_opts, 1) > 1

      operation =
        build_operation(route, verb, needs_verb_suffix, view_map, params_map, status_map)

      {verb, operation}
    end)
  end

  defp count_action_verbs(routes) do
    Enum.reduce(routes, %{}, fn route, acc ->
      Map.update(acc, route.plug_opts, 1, &(&1 + 1))
    end)
  end

  defp build_operation(route, verb, needs_verb_suffix, view_map, params_map, status_map) do
    action = route.plug_opts
    controller = route.plug
    json_view = controller_to_json_view(controller)
    view_info = Map.get(view_map, json_view)
    status = get_in(status_map, [controller, action])

    operation = %{
      operationId: operation_id(controller, action, verb, needs_verb_suffix),
      summary: operation_summary(controller, action),
      responses: build_responses(action, view_info, status)
    }

    path_params = extract_path_params(route.path)

    operation =
      if path_params == [] do
        operation
      else
        Map.put(operation, :parameters, path_params)
      end

    controller_params = get_in(params_map, [controller, action])

    if controller_params && controller_params.fields != [] do
      Map.put(operation, :requestBody, build_request_body(controller_params))
    else
      operation
    end
  end

  defp build_request_body(params_info) do
    properties =
      Map.new(params_info.fields, fn field ->
        name = if is_atom(field.name), do: field.name, else: String.to_atom(field.name)
        {name, field.type}
      end)

    required =
      params_info.fields
      |> Enum.map(fn field ->
        if is_atom(field.name), do: field.name, else: String.to_atom(field.name)
      end)
      |> Enum.sort()

    schema = %{type: "object", properties: properties, required: required}

    %{
      required: true,
      content: %{
        "application/json" => %{schema: schema}
      }
    }
  end

  defp build_responses(action, nil, status) do
    code = to_string(status || default_status(action))

    %{code => %{description: status_description(code), content: default_content()}}
    |> Map.merge(error_responses(action))
  end

  defp build_responses(action, %ViewInfo{actions: actions, module: module}, status) do
    detected_status = status || default_status(action)

    success =
      case {detected_status, Map.get(actions, action)} do
        {204, _} ->
          %{"204" => %{description: "No Content"}}

        {_, %{wrapper_key: wrapper_key, list: list}} ->
          code = to_string(detected_status)
          schema = build_response_schema(module, wrapper_key, list)
          %{code => %{description: status_description(code), content: json_content(schema)}}

        {_, nil} ->
          code = to_string(detected_status)
          %{code => %{description: status_description(code), content: default_content()}}
      end

    Map.merge(success, error_responses(action))
  end

  defp error_responses(action) do
    errors = %{}

    errors =
      if action in [:show, :update, :delete] do
        Map.put(errors, "404", %{description: "Not Found"})
      else
        errors
      end

    if action in [:create, :update] do
      Map.put(errors, "422", %{
        description: "Unprocessable Entity",
        content:
          json_content(%{
            type: "object",
            properties: %{errors: %{type: "object"}}
          })
      })
    else
      errors
    end
  end

  defp build_response_schema(module, wrapper_key, list) do
    schema_name = ViewExtractor.view_module_to_schema_name(module)
    ref = %{"$ref": "#/components/schemas/#{schema_name}"}

    inner = if list, do: %{type: "array", items: ref}, else: ref

    if wrapper_key do
      %{type: "object", properties: %{wrapper_key => inner}}
    else
      inner
    end
  end

  defp default_status(:create), do: 201
  defp default_status(:delete), do: 204
  defp default_status(_), do: 200

  defp status_description("200"), do: "Success"
  defp status_description("201"), do: "Created"
  defp status_description("202"), do: "Accepted"
  defp status_description("204"), do: "No Content"
  defp status_description(_), do: "Success"

  defp json_content(schema), do: %{"application/json" => %{schema: schema}}

  defp default_content, do: %{"application/json" => %{schema: %{type: "object"}}}

  defp extract_path_params(path) do
    Regex.scan(~r/:([a-zA-Z_]+)/, path)
    |> Enum.map(fn [_, name] ->
      %{
        name: name,
        in: "path",
        required: true,
        schema: %{type: "string"}
      }
    end)
  end

  defp phoenix_path_to_openapi(path) do
    Regex.replace(~r/:([a-zA-Z_]+)/, path, "{\\1}")
  end

  defp controller_to_json_view(controller) do
    controller
    |> Atom.to_string()
    |> String.replace("Controller", "JSON")
    |> String.to_existing_atom()
  rescue
    ArgumentError -> nil
  end

  defp route_verb(%{verb: verb}) when is_atom(verb), do: verb |> Atom.to_string()
  defp route_verb(%{verb: verb}) when is_binary(verb), do: String.downcase(verb)

  defp operation_id(controller, action, verb, needs_verb_suffix) do
    controller_name =
      controller
      |> Module.split()
      |> List.last()
      |> String.replace_suffix("Controller", "")

    base = "#{Macro.underscore(controller_name)}_#{action}"
    if needs_verb_suffix, do: "#{base}_#{verb}", else: base
  end

  defp operation_summary(controller, action) do
    resource =
      controller
      |> Module.split()
      |> List.last()
      |> String.replace_suffix("Controller", "")
      |> Macro.underscore()

    case action do
      :index -> "List #{pluralize(resource)}"
      :show -> "Get #{resource}"
      :create -> "Create #{resource}"
      :update -> "Update #{resource}"
      :delete -> "Delete #{resource}"
      other -> "#{other} #{resource}"
    end
  end

  defp pluralize(word) do
    cond do
      String.ends_with?(word, "y") and
          not String.ends_with?(word, ~w(ay ey iy oy uy)) ->
        String.slice(word, 0..-2//1) <> "ies"

      String.ends_with?(word, ~w(s x z ch sh)) ->
        word <> "es"

      true ->
        word <> "s"
    end
  end

  defp drop_nils(map) when is_map(map) do
    map
    |> Enum.reject(fn {_k, v} -> is_nil(v) end)
    |> Enum.into(%{})
  end

  @doc """
  Encodes the spec as JSON.
  """
  @spec to_json(map()) :: String.t()
  def to_json(spec) do
    Jason.encode!(spec, pretty: true)
  end

  @doc """
  Encodes the spec as YAML.
  """
  @spec to_yaml(map()) :: String.t()
  def to_yaml(spec) do
    spec |> Jason.encode!() |> Jason.decode!() |> yaml_encode()
  end

  defp yaml_encode(data), do: to_yaml_str(data, 0)

  defp to_yaml_str(map, indent) when is_map(map) do
    map
    |> Enum.map_join("\n", fn {key, value} ->
      prefix = String.duplicate("  ", indent)

      case value do
        v when is_map(v) and map_size(v) > 0 ->
          "#{prefix}#{key}:\n#{to_yaml_str(v, indent + 1)}"

        v when is_list(v) ->
          items = Enum.map_join(v, "\n", &"#{prefix}  - #{to_yaml_inline(&1)}")
          "#{prefix}#{key}:\n#{items}"

        _ ->
          "#{prefix}#{key}: #{to_yaml_value(value)}"
      end
    end)
  end

  defp to_yaml_value(nil), do: "null"
  defp to_yaml_value(true), do: "true"
  defp to_yaml_value(false), do: "false"
  defp to_yaml_value(v) when is_binary(v), do: inspect(v)
  defp to_yaml_value(v), do: "#{v}"

  defp to_yaml_inline(v) when is_binary(v), do: inspect(v)
  defp to_yaml_inline(v), do: "#{v}"
end
