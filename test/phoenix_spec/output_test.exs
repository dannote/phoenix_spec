defmodule PhoenixSpec.OutputTest do
  use ExUnit.Case, async: true

  test "full JSON output is valid and complete" do
    spec =
      PhoenixSpec.OpenAPI.generate(
        router: TestAppWeb.Router,
        title: "TestApp API",
        version: "0.1.0"
      )

    json = PhoenixSpec.OpenAPI.to_json(spec)
    {:ok, decoded} = Jason.decode(json)

    assert decoded["openapi"] == "3.1.0"
    assert decoded["info"]["title"] == "TestApp API"

    schemas = decoded["components"]["schemas"]
    assert Map.has_key?(schemas, "Post")
    assert Map.has_key?(schemas, "User")
    assert Map.has_key?(schemas, "Comment")

    post = schemas["Post"]
    assert post["properties"]["id"] == %{"type" => "integer"}
    assert post["properties"]["title"] == %{"type" => "string"}
    assert post["properties"]["published_at"] == %{"type" => "string", "format" => "date-time"}
    assert post["properties"]["author"] == %{"$ref" => "#/components/schemas/User"}

    paths = decoded["paths"]
    assert Map.has_key?(paths, "/api/posts")
    assert Map.has_key?(paths, "/api/posts/{id}")
    assert Map.has_key?(paths, "/api/users")

    assert String.length(json) > 100
  end
end
