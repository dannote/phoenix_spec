defmodule PhoenixSpec.SchemaResolverTest do
  use ExUnit.Case, async: true

  alias PhoenixSpec.SchemaResolver

  test "extracts fields from Ecto schema" do
    fields = SchemaResolver.fields(TestApp.Post)

    assert fields[:title] == :string
    assert fields[:body] == :string
    assert fields[:view_count] == :integer
    assert fields[:published] == :boolean
    assert fields[:published_at] == :utc_datetime
  end

  test "extracts primary key" do
    assert SchemaResolver.primary_key(TestApp.Post) == [:id]
  end

  test "extracts associations" do
    assocs = SchemaResolver.associations(TestApp.Post)

    assert :author in assocs
    assert :comments in assocs
  end

  test "returns association metadata" do
    assoc = SchemaResolver.association(TestApp.Post, :author)

    assert assoc.related == TestApp.User
    assert assoc.cardinality == :one
  end

  test "detects Ecto schemas" do
    assert SchemaResolver.ecto_schema?(TestApp.Post)
    refute SchemaResolver.ecto_schema?(String)
  end
end
