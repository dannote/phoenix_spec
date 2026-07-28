defmodule PhoenixSpec.ParamsExtractorTest do
  use ExUnit.Case, async: true

  alias PhoenixSpec.ParamsExtractor
  alias PhoenixSpec.ParamsExtractor.ParamsInfo

  test "extracts changeset fields wrapped under param key" do
    params = ParamsExtractor.extract(TestAppWeb.PostController)

    assert %ParamsInfo{} = params[:create]
    assert [wrapper] = params[:create].fields
    assert wrapper.name == "post"
    assert wrapper.type.type == "object"

    inner_fields = wrapper.type.properties
    assert inner_fields[:title] == %{type: "string"}
    assert inner_fields[:body] == %{type: "string"}
    assert inner_fields[:published] == %{type: "boolean"}
  end

  test "resolves field types from Ecto schema in wrapper" do
    params = ParamsExtractor.extract(TestAppWeb.PostController)
    [wrapper] = params[:create].fields

    inner = wrapper.type.properties
    assert inner[:title] == %{type: "string"}
    assert inner[:body] == %{type: "string"}
    assert inner[:published] == %{type: "boolean"}
  end

  test "does not treat flat parameter maps as wrapper keys" do
    params = ParamsExtractor.extract(TestAppWeb.FlatParamsController)

    assert Enum.map(params.create.fields, & &1.name) == [:title, :body]
  end

  test "update action wraps changeset fields" do
    params = ParamsExtractor.extract(TestAppWeb.PostController)

    assert %ParamsInfo{} = params[:update]
    [wrapper] = params[:update].fields
    assert wrapper.name == "post"

    inner = wrapper.type.properties
    assert Map.has_key?(inner, :title)
    assert Map.has_key?(inner, :body)
    refute Map.has_key?(inner, :published)
  end
end
