defmodule PhoenixSpec.MetadataTest do
  use ExUnit.Case, async: true

  alias PhoenixSpec.{Metadata, OpenAPI, ViewExtractor}

  test "annotates inferred schemas, embedded objects, references and arrays" do
    spec = OpenAPI.generate(router: TestAppWeb.MetadataRouter, description: "API docs")
    assert spec.info.description == "API docs"
    assert Map.has_key?(spec.components.schemas, "User")
    schema = spec.components.schemas["Metadata"]
    assert schema.description == "A documented user"
    assert schema.additionalProperties == false
    assert schema.examples == [%{name: "Ada"}]

    assert schema.properties.name == %{
             type: "string",
             description: "Display name",
             examples: ["Ada"]
           }

    assert schema.properties.address.type == "object"
    assert schema.properties.address.properties.street.type == "string"
    assert schema.properties.address.additionalProperties == false

    assert schema.properties.author == %{
             "$ref": "#/components/schemas/User",
             description: "Author",
             examples: [%{id: 1}]
           }

    assert schema.properties.authors == %{
             type: "array",
             items: %{"$ref": "#/components/schemas/User"},
             description: "Authors"
           }

    assert schema.properties.settings.additionalProperties == %{type: "string"}
    assert schema.properties.active.examples == [false, nil]
    assert "name" in Enum.map(schema.required, &to_string/1)

    assert Jason.decode!(OpenAPI.to_json(spec))["components"]["schemas"]["Metadata"][
             "additionalProperties"
           ] == false

    yaml = spec |> OpenAPI.to_yaml() |> YamlElixir.read_from_string!()
    assert yaml["components"]["schemas"]["Metadata"]["additionalProperties"] == false

    assert yaml["components"]["schemas"]["Metadata"]["properties"]["active"]["examples"] == [
             false,
             nil
           ]
  end

  test "closes each polymorphic variant rather than the oneOf container" do
    spec = OpenAPI.generate(router: TestAppWeb.MetadataRouter)
    schema = spec.components.schemas["MetadataVariant"]
    assert schema.description == "Message"
    refute Map.has_key?(schema, :additionalProperties)
    assert [_, _] = schema.oneOf

    for variant <- schema.oneOf do
      assert variant.additionalProperties == false
      assert variant.properties.id.description == "Identifier"
      assert variant.properties.id.type == "integer"
    end
  end

  test "keeps metadata separate from inferred field types" do
    info = ViewExtractor.extract(TestAppWeb.MetadataJSON)
    name = Enum.find(info.fields, &(&1.name == :name))
    assert name.type == %{type: "string"}
    assert name.metadata.examples == ["Ada"]
    assert PhoenixSpec.TypeScript.generate(router: TestAppWeb.MetadataRouter) =~ "name: string;"
  end

  test "collects literal metadata only from the current module" do
    ast =
      Code.string_to_quoted!("""
      defmodule Example do
        @schema_metadata examples: [%{"delta" => -2, "active" => false, "value" => nil}]
        defmodule Nested do
          @schema_metadata description: "Not the parent"
        end
      end
      """)

    metadata = Metadata.collect(ast, :schema_metadata) |> Metadata.validate!()
    assert metadata == %{examples: [%{"delta" => -2, "active" => false, "value" => nil}]}
  end

  test "accepts boolean and schema-valued additionalProperties" do
    for value <- [true, false, %{type: "string"}, %{type: "object", additionalProperties: false}] do
      assert Metadata.validate!(%{additionalProperties: value}) == %{additionalProperties: value}
    end
  end

  test "omits document descriptions when not supplied" do
    refute Map.has_key?(OpenAPI.generate(router: TestAppWeb.MetadataRouter).info, :description)
  end

  test "rejects expressions and invalid metadata without evaluating source" do
    for source <- [
          "@schema_metadata examples: [send(self(), :evaluated)]",
          "@schema_metadata examples: [1 + 2]"
        ] do
      assert_raise ArgumentError, fn ->
        source |> Code.string_to_quoted!() |> Metadata.collect(:schema_metadata)
      end
    end

    refute_received :evaluated

    for value <- [
          %{description: 1},
          %{examples: "not a list"},
          %{additionalProperties: nil},
          %{type: "integer"}
        ] do
      assert_raise ArgumentError, fn -> Metadata.validate!(value) end
    end
  end
end
