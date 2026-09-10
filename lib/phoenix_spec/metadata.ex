defmodule PhoenixSpec.Metadata do
  @moduledoc false

  # Decode only literal data. Never evaluate expressions from application source.
  def collect(body, attribute) do
    body
    |> expressions()
    |> Enum.reduce(%{}, fn
      {:@, _, [{^attribute, _, [value]}]}, acc ->
        Map.merge(acc, value |> literal!() |> keyword_map!())

      _, acc ->
        acc
    end)
  end

  def validate!(metadata) do
    Enum.each(metadata, fn
      {:description, value} when is_binary(value) -> :ok
      {:examples, value} when is_list(value) -> json!(value)
      {:additionalProperties, value} when is_boolean(value) or is_map(value) -> json!(value)
      {key, _} -> raise ArgumentError, "invalid PhoenixSpec metadata: #{inspect(key)}"
    end)

    metadata
  end

  def keyword_map!(value) when is_list(value) do
    if Keyword.keyword?(value), do: Map.new(value), else: invalid!()
  end

  def keyword_map!(_), do: invalid!()

  defp expressions({:defmodule, _, [_, [do: body]]}), do: expressions(body)
  defp expressions({:__block__, _, expressions}), do: expressions
  defp expressions(expression), do: [expression]

  defp literal!({:%{}, _, pairs}),
    do: Map.new(pairs, fn {key, value} -> {literal!(key), literal!(value)} end)

  defp literal!({sign, _, [value]}) when sign in [:+, :-] and is_number(value),
    do: if(sign == :-, do: -value, else: value)

  defp literal!({key, value}), do: {literal!(key), literal!(value)}
  defp literal!(value) when is_list(value), do: Enum.map(value, &literal!/1)
  defp literal!(value) when is_atom(value) or is_binary(value) or is_number(value), do: value
  defp literal!(_), do: invalid!()

  defp json!(value)
       when is_binary(value) or is_number(value) or is_boolean(value) or is_nil(value),
       do: :ok

  defp json!(value) when is_list(value), do: Enum.each(value, &json!/1)

  defp json!(value) when is_map(value) do
    Enum.each(value, fn {key, inner} ->
      if not (is_binary(key) or is_atom(key)), do: invalid!()
      json!(inner)
    end)
  end

  defp json!(_), do: invalid!()

  defp invalid!,
    do:
      raise(
        ArgumentError,
        "PhoenixSpec metadata must contain literal JSON data in a keyword list"
      )
end
