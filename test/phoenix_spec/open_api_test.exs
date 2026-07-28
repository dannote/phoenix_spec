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
    assert Map.has_key?(spec.paths, "/api/inline-posts/{id}")
  end

  test "generates schemas and responses for inline JSON controllers", %{spec: spec} do
    schema = spec.components.schemas["InlinePost"]
    assert schema.properties.id == %{type: "integer"}
    assert schema.properties.title == %{type: "string"}

    operation = spec.paths["/api/inline-posts/{id}"]["get"]
    response_schema = operation.responses["200"].content["application/json"].schema
    assert response_schema.properties.data == %{"$ref": "#/components/schemas/InlinePost"}
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

    post_wrapper = schema.properties["post"]
    assert post_wrapper.type == "object"
    assert post_wrapper.properties[:title] == %{type: "string"}
    assert post_wrapper.properties[:published] == %{type: "boolean"}
  end

  test "create action returns 201 status", %{spec: spec} do
    post_op = spec.paths["/api/posts"]["post"]
    assert Map.has_key?(post_op.responses, "201")
    refute Map.has_key?(post_op.responses, "200")
    assert post_op.responses["201"].description == "Created"
  end

  test "delete action returns 204 with no content", %{spec: spec} do
    delete_op = spec.paths["/api/posts/{id}"]["delete"]
    assert Map.has_key?(delete_op.responses, "204")
    assert delete_op.responses["204"].description == "No Content"
    refute Map.has_key?(delete_op.responses["204"], :content)
  end

  test "update action returns 200", %{spec: spec} do
    put_op = spec.paths["/api/posts/{id}"]["put"]
    assert Map.has_key?(put_op.responses, "200")
  end

  test "embedded_one generates inline object schema", %{spec: spec} do
    user_detail = spec.components.schemas["UserDetail"]
    address = user_detail.properties[:address]

    assert address.type == "object"
    assert address.properties[:street] == %{type: "string"}
    assert address.properties[:city] == %{type: "string"}
    assert address.properties[:zip] == %{type: "string"}
  end

  test "embedded_many generates array of inline objects", %{spec: spec} do
    user_detail = spec.components.schemas["UserDetail"]
    links = user_detail.properties[:social_links]

    assert links.type == "array"
    assert links.items.type == "object"
    assert links.items.properties[:platform] == %{type: "string"}
    assert links.items.properties[:url] == %{type: "string"}
  end

  test "@field_types annotation resolves computed field types in schema", %{spec: spec} do
    user_detail = spec.components.schemas["UserDetail"]

    assert user_detail.properties[:reading_time] == %{type: "integer"}
    assert user_detail.properties[:avatar_url] == %{type: "string"}
  end

  test "operations have summary", %{spec: spec} do
    assert spec.paths["/api/posts"]["get"].summary == "List posts"
    assert spec.paths["/api/posts"]["post"].summary == "Create post"
    assert spec.paths["/api/posts/{id}"]["get"].summary == "Get post"
    assert spec.paths["/api/posts/{id}"]["put"].summary == "Update post"
    assert spec.paths["/api/posts/{id}"]["delete"].summary == "Delete post"
  end

  test "patch and put for same action have unique operationIds", %{spec: spec} do
    put_id = spec.paths["/api/posts/{id}"]["put"].operationId
    patch_id = spec.paths["/api/posts/{id}"]["patch"].operationId

    assert put_id != patch_id
    assert put_id == "post_update_put"
    assert patch_id == "post_update_patch"
  end

  test "create responds with 422 error schema", %{spec: spec} do
    post_op = spec.paths["/api/posts"]["post"]
    assert Map.has_key?(post_op.responses, "422")
    assert post_op.responses["422"].description == "Unprocessable Entity"

    error_schema = post_op.responses["422"].content["application/json"].schema
    assert error_schema.properties.errors == %{type: "object"}
  end

  test "show responds with 404", %{spec: spec} do
    get_op = spec.paths["/api/posts/{id}"]["get"]
    assert Map.has_key?(get_op.responses, "404")
    assert get_op.responses["404"].description == "Not Found"
  end

  test "delete responds with 404", %{spec: spec} do
    delete_op = spec.paths["/api/posts/{id}"]["delete"]
    assert Map.has_key?(delete_op.responses, "404")
  end

  test "update responds with 422 and 404", %{spec: spec} do
    put_op = spec.paths["/api/posts/{id}"]["put"]
    assert Map.has_key?(put_op.responses, "422")
    assert Map.has_key?(put_op.responses, "404")
  end

  test "index does not have error responses", %{spec: spec} do
    get_op = spec.paths["/api/posts"]["get"]
    refute Map.has_key?(get_op.responses, "404")
    refute Map.has_key?(get_op.responses, "422")
  end

  test "polymorphic data/1 generates oneOf schema", %{spec: spec} do
    message = spec.components.schemas["Message"]

    assert Map.has_key?(message, :oneOf)
    [text_schema, image_schema] = message.oneOf
    assert text_schema.type == "object"
    assert Map.has_key?(text_schema.properties, :text)
    assert Map.has_key?(text_schema.properties, :sender)

    assert image_schema.type == "object"
    assert Map.has_key?(image_schema.properties, :url)
    assert Map.has_key?(image_schema.properties, :width)
    assert Map.has_key?(image_schema.properties, :height)
  end

  test "serializes to valid JSON", %{spec: spec} do
    json = OpenAPI.to_json(spec)
    assert {:ok, decoded} = Jason.decode(json)
    assert decoded["openapi"] == "3.1.0"
  end
end
