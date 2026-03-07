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

  test "extracts enum fields" do
    info = ViewExtractor.extract(TestAppWeb.PostJSON)
    field_map = Map.new(info.fields, &{&1.name, &1})

    assert field_map[:status].type.type == "string"
    assert "draft" in field_map[:status].type.enum
  end

  test "extracts array fields" do
    info = ViewExtractor.extract(TestAppWeb.PostJSON)
    field_map = Map.new(info.fields, &{&1.name, &1})

    assert field_map[:tags].type == %{type: "array", items: %{type: "string"}}
  end

  test "computed fields get empty type when unannotated" do
    info = ViewExtractor.extract(TestAppWeb.PostJSON)
    field_map = Map.new(info.fields, &{&1.name, &1})

    assert field_map[:reading_time].type == %{}
  end

  test "@field_types annotation resolves computed field types" do
    info = ViewExtractor.extract(TestAppWeb.UserDetailJSON)
    field_map = Map.new(info.fields, &{&1.name, &1})

    assert field_map[:reading_time].type == %{type: "integer"}
    assert field_map[:avatar_url].type == %{type: "string"}
  end

  test "extracts embedded_one fields" do
    info = ViewExtractor.extract(TestAppWeb.UserDetailJSON)
    field_map = Map.new(info.fields, &{&1.name, &1})

    assert field_map[:address].type.type == "embedded"
    assert field_map[:address].type.cardinality == :one
    assert field_map[:address].type.schema == TestApp.Address
  end

  test "extracts embedded_many fields" do
    info = ViewExtractor.extract(TestAppWeb.UserDetailJSON)
    field_map = Map.new(info.fields, &{&1.name, &1})

    assert field_map[:social_links].type.type == "embedded"
    assert field_map[:social_links].type.cardinality == :many
    assert field_map[:social_links].type.schema == TestApp.SocialLink
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

  test "detects @optional attribute fields" do
    info = ViewExtractor.extract(TestAppWeb.UserDetailJSON)
    field_map = Map.new(info.fields, &{&1.name, &1})

    refute field_map[:age].required
    refute field_map[:avatar_url].required
    assert field_map[:id].required
    assert field_map[:name].required
  end

  test "detects inline conditional as optional" do
    info = ViewExtractor.extract(TestAppWeb.UserDetailJSON)
    field_map = Map.new(info.fields, &{&1.name, &1})

    # avatar_url uses `if(...)` — detected as conditional even without @optional
    refute field_map[:avatar_url].required
  end

  test "derives schema name from view module" do
    assert ViewExtractor.view_module_to_schema_name(TestAppWeb.PostJSON) == "Post"
    assert ViewExtractor.view_module_to_schema_name(TestAppWeb.UserJSON) == "User"
    assert ViewExtractor.view_module_to_schema_name(TestAppWeb.CommentJSON) == "Comment"
  end

  test "resolves fields through association traversal" do
    info = ViewExtractor.extract(TestAppWeb.CommentJSON)
    field_map = Map.new(info.fields, &{&1.name, &1})

    assert field_map[:author_name].type == %{type: "string"}
    assert field_map[:author_email].type == %{type: "string"}
    assert field_map[:post_title].type == %{type: "string"}
  end

  test "infers schema from alias when data/1 has no struct match" do
    info = ViewExtractor.extract(TestAppWeb.CommentDetailJSON)

    assert info.schema == TestApp.Comment
    field_map = Map.new(info.fields, &{&1.name, &1})
    assert field_map[:id].type == %{type: "integer"}
    assert field_map[:body].type == %{type: "string"}
  end

  test "extracts fields from inline map in show action (no data/1)" do
    info = ViewExtractor.extract(TestAppWeb.PostSummaryJSON)

    assert info.schema == TestApp.Post
    field_map = Map.new(info.fields, &{&1.name, &1})
    assert field_map[:id].type == %{type: "integer"}
    assert field_map[:title].type == %{type: "string"}
    assert field_map[:published].type == %{type: "boolean"}
  end

  test "detects inline map literals as object type" do
    info = ViewExtractor.extract(TestAppWeb.PostMetaJSON)

    field_map = Map.new(info.fields, &{&1.name, &1})
    assert field_map[:author].type.type == "object"
    assert field_map[:author].type.properties.name == %{type: "string"}
    assert field_map[:author].type.properties.email == %{type: "string"}
  end

  test "nested inline objects resolve schema field types" do
    info = ViewExtractor.extract(TestAppWeb.PostMetaJSON)

    field_map = Map.new(info.fields, &{&1.name, &1})
    assert field_map[:stats].type.type == "object"
    assert field_map[:stats].type.properties.views == %{type: "integer"}
  end
end
