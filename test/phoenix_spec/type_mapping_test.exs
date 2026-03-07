defmodule PhoenixSpec.TypeMappingTest do
  use ExUnit.Case, async: true

  alias PhoenixSpec.TypeMapping

  test "maps basic Ecto types to OpenAPI" do
    assert TypeMapping.to_openapi(:string) == %{type: "string"}
    assert TypeMapping.to_openapi(:integer) == %{type: "integer"}
    assert TypeMapping.to_openapi(:float) == %{type: "number", format: "double"}
    assert TypeMapping.to_openapi(:boolean) == %{type: "boolean"}
    assert TypeMapping.to_openapi(:decimal) == %{type: "string", format: "decimal"}
    assert TypeMapping.to_openapi(:binary) == %{type: "string", format: "binary"}
  end

  test "maps ID types" do
    assert TypeMapping.to_openapi(:id) == %{type: "integer"}
    assert TypeMapping.to_openapi(:binary_id) == %{type: "string", format: "uuid"}
  end

  test "maps date/time types" do
    assert TypeMapping.to_openapi(:date) == %{type: "string", format: "date"}
    assert TypeMapping.to_openapi(:utc_datetime) == %{type: "string", format: "date-time"}
    assert TypeMapping.to_openapi(:utc_datetime_usec) == %{type: "string", format: "date-time"}
    assert TypeMapping.to_openapi(:naive_datetime) == %{type: "string", format: "date-time"}
    assert TypeMapping.to_openapi(:time) == %{type: "string", format: "time"}
  end

  test "maps composite types" do
    assert TypeMapping.to_openapi({:array, :string}) == %{
             type: "array",
             items: %{type: "string"}
           }

    assert TypeMapping.to_openapi({:map, :string}) == %{
             type: "object",
             additionalProperties: %{type: "string"}
           }

    assert TypeMapping.to_openapi(:map) == %{type: "object"}
  end

  test "maps Ecto.Enum to string with enum values" do
    enum_type = TestApp.Post.__schema__(:type, :status)

    result = TypeMapping.to_openapi(enum_type)
    assert result.type == "string"
    assert "draft" in result.enum
    assert "published" in result.enum
    assert "archived" in result.enum
  end

  test "unknown types return empty map" do
    assert TypeMapping.to_openapi(:unknown_type) == %{}
  end
end
