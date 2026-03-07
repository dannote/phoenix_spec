defmodule PhoenixSpec.OpenAPITest do
  use ExUnit.Case, async: true

  alias PhoenixSpec.OpenAPI

  setup_all do
    spec =
      OpenAPI.generate(
        router: TestAppWeb.Router,
        title: "TestApp API",
        version: "0.1.0"
      )

    %{spec: spec}
  end

  test "generates valid OpenAPI 3.1 structure", %{spec: spec} do
    assert spec.openapi == "3.1.0"
    assert spec.info.title == "TestApp API"
    assert spec.info.version == "0.1.0"
    assert is_map(spec.paths)
    assert is_map(spec.components.schemas)
  end

  test "generates schemas for all JSON views", %{spec: spec} do
    schemas = spec.components.schemas

    assert Map.has_key?(schemas, "Post")
    assert Map.has_key?(schemas, "User")
    assert Map.has_key?(schemas, "Comment")
  end

  test "Post schema has correct properties", %{spec: spec} do
    post_schema = spec.components.schemas["Post"]

    assert post_schema.type == "object"
    props = post_schema.properties

    assert props[:id] == %{type: "integer"}
    assert props[:title] == %{type: "string"}
    assert props[:published] == %{type: "boolean"}
    assert props[:published_at] == %{type: "string", format: "date-time"}
  end

  test "Post schema references User via author field", %{spec: spec} do
    post_schema = spec.components.schemas["Post"]
    author_prop = post_schema.properties[:author]

    assert author_prop == %{"$ref": "#/components/schemas/User"}
  end

  test "generates paths from router", %{spec: spec} do
    assert Map.has_key?(spec.paths, "/api/posts")
    assert Map.has_key?(spec.paths, "/api/posts/{id}")
    assert Map.has_key?(spec.paths, "/api/users")
    assert Map.has_key?(spec.paths, "/api/users/{id}")
  end

  test "index paths have GET with array response", %{spec: spec} do
    get_op = spec.paths["/api/posts"]["get"]

    assert get_op.operationId == "post_index"
    response_schema = get_op.responses["200"].content["application/json"].schema

    assert response_schema.type == "object"
    assert response_schema.properties[:data].type == "array"
    assert response_schema.properties[:data].items == %{"$ref": "#/components/schemas/Post"}
  end

  test "show paths have GET with single object response", %{spec: spec} do
    get_op = spec.paths["/api/posts/{id}"]["get"]

    assert get_op.operationId == "post_show"
    assert length(get_op.parameters) == 1

    [param] = get_op.parameters
    assert param.name == "id"
    assert param.in == "path"
    assert param.required == true
  end

  test "create paths have POST with request body", %{spec: spec} do
    post_op = spec.paths["/api/posts"]["post"]
    assert post_op.operationId == "post_create"

    request_body = post_op.requestBody
    assert request_body.required == true

    schema = request_body.content["application/json"].schema
    assert schema.type == "object"
    assert schema.properties[:title] == %{type: "string"}
    assert schema.properties[:published] == %{type: "boolean"}
  end

  test "serializes to valid JSON", %{spec: spec} do
    json = OpenAPI.to_json(spec)
    assert {:ok, decoded} = Jason.decode(json)
    assert decoded["openapi"] == "3.1.0"
  end
end
