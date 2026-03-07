defmodule PhoenixSpec.OpenAPI do
  @moduledoc """
  Generates an OpenAPI 3.1 specification from extracted view and schema information.
  """

  alias PhoenixSpec.{Discovery, ParamsExtractor, ViewExtractor}
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
    schemas = build_schemas(view_infos)
    paths = build_paths(router, view_infos, params_map)

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

  defp field_to_property(%Field{type: type}) when is_map(type) and map_size(type) > 0 do
    type
  end

  defp field_to_property(%Field{}) do
    %{}
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

  defp build_paths(router, view_infos, params_map) do
    view_map = build_view_lookup(view_infos)

    router.__routes__()
    |> Enum.filter(&json_route?/1)
    |> Enum.group_by(& &1.path)
    |> Map.new(fn {path, routes} ->
      openapi_path = phoenix_path_to_openapi(path)
      operations = build_operations(routes, view_map, params_map)
      {openapi_path, operations}
    end)
  end

  defp build_view_lookup(view_infos) do
    Map.new(view_infos, fn %ViewInfo{module: module} = info ->
      {module, info}
    end)
  end

  defp json_route?(%{plug: plug}) do
    module_name = Atom.to_string(plug)
    String.contains?(module_name, "Controller")
  end

  defp build_operations(routes, view_map, params_map) do
    Map.new(routes, fn route ->
      verb = route_verb(route)
      operation = build_operation(route, view_map, params_map)
      {verb, operation}
    end)
  end

  defp build_operation(route, view_map, params_map) do
    action = route.plug_opts
    controller = route.plug
    json_view = controller_to_json_view(controller)
    view_info = Map.get(view_map, json_view)

    operation = %{
      operationId: operation_id(controller, action),
      responses: build_responses(action, view_info)
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

  defp build_responses(action, nil) do
    %{"200" => %{description: "Success", content: default_content(action)}}
  end

  defp build_responses(action, %ViewInfo{actions: actions, module: module} = _view_info) do
    schema_name = ViewExtractor.view_module_to_schema_name(module)

    case Map.get(actions, action) do
      %{wrapper_key: wrapper_key, list: true} ->
        inner = %{type: "array", items: %{"$ref": "#/components/schemas/#{schema_name}"}}

        schema =
          if wrapper_key do
            %{type: "object", properties: %{wrapper_key => inner}}
          else
            inner
          end

        status = if action == :create, do: "201", else: "200"

        %{
          status => %{description: "Success", content: %{"application/json" => %{schema: schema}}}
        }

      %{wrapper_key: wrapper_key, list: false} ->
        ref_schema = %{"$ref": "#/components/schemas/#{schema_name}"}

        schema =
          if wrapper_key do
            %{type: "object", properties: %{wrapper_key => ref_schema}}
          else
            ref_schema
          end

        status = if action == :create, do: "201", else: "200"

        %{
          status => %{description: "Success", content: %{"application/json" => %{schema: schema}}}
        }

      nil ->
        %{"200" => %{description: "Success", content: default_content(action)}}
    end
  end

  defp default_content(_action) do
    %{"application/json" => %{schema: %{type: "object"}}}
  end

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

  defp operation_id(controller, action) do
    controller_name =
      controller
      |> Module.split()
      |> List.last()
      |> String.replace_suffix("Controller", "")

    "#{Macro.underscore(controller_name)}_#{action}"
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
