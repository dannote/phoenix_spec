defmodule PhoenixSpec.ViewExtractorTest do
  use ExUnit.Case, async: true

  alias PhoenixSpec.ViewExtractor
  alias PhoenixSpec.ViewExtractor.ViewInfo

  test "extracts schema from PostJSON" do
    info = ViewExtractor.extract(TestAppWeb.PostJSON)

    assert %ViewInfo{} = info
    assert info.schema == TestApp.Post
  end

  test "extracts fields with correct types from PostJSON" do
    info = ViewExtractor.extract(TestAppWeb.PostJSON)

    field_map = Map.new(info.fields, &{&1.name, &1})

    assert field_map[:id].type == %{type: "integer"}
    assert field_map[:title].type == %{type: "string"}
    assert field_map[:body].type == %{type: "string"}
    assert field_map[:view_count].type == %{type: "integer"}
    assert field_map[:published].type == %{type: "boolean"}
    assert field_map[:published_at].type == %{type: "string", format: "date-time"}
  end

  test "detects reference to nested view (author)" do
    info = ViewExtractor.extract(TestAppWeb.PostJSON)

    field_map = Map.new(info.fields, &{&1.name, &1})

    assert field_map[:author].ref == "User"
  end

  test "extracts actions from PostJSON" do
    info = ViewExtractor.extract(TestAppWeb.PostJSON)

    assert Map.has_key?(info.actions, :index)
    assert Map.has_key?(info.actions, :show)
    assert Map.has_key?(info.actions, :create)

    assert info.actions[:index].list == true
    assert info.actions[:index].wrapper_key == :data

    assert info.actions[:show].list == false
    assert info.actions[:show].wrapper_key == :data
  end

  test "extracts UserJSON fields" do
    info = ViewExtractor.extract(TestAppWeb.UserJSON)

    field_map = Map.new(info.fields, &{&1.name, &1})

    assert field_map[:id].type == %{type: "integer"}
    assert field_map[:name].type == %{type: "string"}
    assert field_map[:email].type == %{type: "string"}
  end

  test "derives schema name from view module" do
    assert ViewExtractor.view_module_to_schema_name(TestAppWeb.PostJSON) == "Post"
    assert ViewExtractor.view_module_to_schema_name(TestAppWeb.UserJSON) == "User"
    assert ViewExtractor.view_module_to_schema_name(TestAppWeb.CommentJSON) == "Comment"
  end
end
