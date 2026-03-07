defmodule PhoenixSpec.ParamsExtractorTest do
  use ExUnit.Case, async: true

  alias PhoenixSpec.ParamsExtractor
  alias PhoenixSpec.ParamsExtractor.ParamsInfo

  test "extracts changeset fields from create action" do
    params = ParamsExtractor.extract(TestAppWeb.PostController)

    assert %ParamsInfo{} = params[:create]
    field_names = Enum.map(params[:create].fields, & &1.name)

    assert :title in field_names
    assert :body in field_names
    assert :published in field_names
  end

  test "resolves field types from Ecto schema" do
    params = ParamsExtractor.extract(TestAppWeb.PostController)
    fields = Map.new(params[:create].fields, &{&1.name, &1})

    assert fields[:title].type == %{type: "string"}
    assert fields[:body].type == %{type: "string"}
    assert fields[:published].type == %{type: "boolean"}
  end

  test "extracts update action fields" do
    params = ParamsExtractor.extract(TestAppWeb.PostController)

    assert %ParamsInfo{} = params[:update]
    field_names = Enum.map(params[:update].fields, & &1.name)

    assert :title in field_names
    assert :body in field_names
    refute :published in field_names
  end
end
