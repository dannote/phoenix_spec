defmodule PhoenixSpec.TypeMapping do
  @moduledoc """
  Maps Ecto schema types to OpenAPI 3.1 schema objects.
  """

  @spec to_openapi(atom() | tuple()) :: map()
  def to_openapi(:id), do: %{type: "integer"}
  def to_openapi(:binary_id), do: %{type: "string", format: "uuid"}
  def to_openapi(:integer), do: %{type: "integer"}
  def to_openapi(:float), do: %{type: "number", format: "double"}
  def to_openapi(:decimal), do: %{type: "string", format: "decimal"}
  def to_openapi(:boolean), do: %{type: "boolean"}
  def to_openapi(:string), do: %{type: "string"}
  def to_openapi(:binary), do: %{type: "string", format: "binary"}
  def to_openapi(:date), do: %{type: "string", format: "date"}
  def to_openapi(:time), do: %{type: "string", format: "time"}
  def to_openapi(:utc_datetime), do: %{type: "string", format: "date-time"}
  def to_openapi(:utc_datetime_usec), do: %{type: "string", format: "date-time"}
  def to_openapi(:naive_datetime), do: %{type: "string", format: "date-time"}
  def to_openapi(:naive_datetime_usec), do: %{type: "string", format: "date-time"}
  def to_openapi(:map), do: %{type: "object"}
  def to_openapi({:map, inner}), do: %{type: "object", additionalProperties: to_openapi(inner)}
  def to_openapi({:array, inner}), do: %{type: "array", items: to_openapi(inner)}

  def to_openapi({:parameterized, {Ecto.Enum, %{mappings: mappings}}}) do
    values = Keyword.keys(mappings) |> Enum.map(&Atom.to_string/1)
    %{type: "string", enum: values}
  end

  def to_openapi({:parameterized, {Ecto.Enum, %{on_dump: on_dump}}}) do
    values = Map.keys(on_dump) |> Enum.map(&Atom.to_string/1)
    %{type: "string", enum: values}
  end

  def to_openapi({:parameterized, {Ecto.Embedded, %{cardinality: :one, related: schema}}}) do
    %{type: "embedded", cardinality: :one, schema: schema}
  end

  def to_openapi({:parameterized, {Ecto.Embedded, %{cardinality: :many, related: schema}}}) do
    %{type: "embedded", cardinality: :many, schema: schema}
  end

  def to_openapi(_unknown), do: %{}
end
