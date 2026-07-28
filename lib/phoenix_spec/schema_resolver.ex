defmodule PhoenixSpec.SchemaResolver do
  @moduledoc """
  Introspects Ecto schemas to extract field names, types, and associations.
  """

  @doc """
  Returns a map of field names to their Ecto types for the given schema module.
  """
  @spec fields(module()) :: %{atom() => atom() | tuple()}
  def fields(schema) do
    schema.__schema__(:fields)
    |> Map.new(fn field -> {field, schema.__schema__(:type, field)} end)
  end

  @doc """
  Returns the primary key fields for the given schema.
  """
  @spec primary_key(module()) :: [atom()]
  def primary_key(schema) do
    schema.__schema__(:primary_key)
  end

  @doc """
  Returns association metadata for the given schema and field.
  """
  @spec association(module(), atom()) :: map() | nil
  def association(schema, field) do
    schema.__schema__(:association, field)
  end

  @doc """
  Returns all association fields for the given schema.
  """
  @spec associations(module()) :: [atom()]
  def associations(schema) do
    schema.__schema__(:associations)
  end

  @doc """
  Checks if the module is an Ecto schema.
  """
  @spec ecto_schema?(module()) :: boolean()
  def ecto_schema?(module) do
    Code.ensure_loaded?(module) and function_exported?(module, :__schema__, 1)
  end
end
