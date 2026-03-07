defmodule PhoenixSpec.StatusExtractor do
  @moduledoc """
  Extracts HTTP response status codes from Phoenix controller actions.

  Detects `put_status/2` and `send_resp/3` calls in controller source.
  """

  alias PhoenixSpec.AstHelpers

  @status_codes %{
    ok: 200,
    created: 201,
    accepted: 202,
    no_content: 204,
    moved_permanently: 301,
    found: 302,
    see_other: 303,
    not_modified: 304,
    bad_request: 400,
    unauthorized: 401,
    forbidden: 403,
    not_found: 404,
    unprocessable_entity: 422,
    internal_server_error: 500
  }

  @doc """
  Extracts status codes from controller action bodies.
  Returns a map of action names to detected status codes.
  """
  @spec extract(module()) :: %{atom() => integer()}
  def extract(controller) do
    case AstHelpers.parse_module_source(controller) do
      {:ok, _module, ast} -> extract_from_ast(controller, ast)
      :error -> %{}
    end
  end

  defp extract_from_ast(controller, ast) do
    module_ast = AstHelpers.find_module_ast(ast, controller)
    body = module_ast || ast

    {_, actions} =
      Macro.prewalk(body, [], fn
        {:def, _, [{name, _, _args}, action_body]} = node, acc when is_atom(name) ->
          case detect_status(action_body) do
            nil -> {node, acc}
            status -> {node, [{name, status} | acc]}
          end

        node, acc ->
          {node, acc}
      end)

    Map.new(actions)
  end

  defp detect_status(do: body), do: detect_status(body)

  defp detect_status(body) do
    {_, status} =
      Macro.prewalk(body, nil, fn
        # put_status(conn, :created) — direct 2-arg call
        {:put_status, _, [_, status_arg]} = node, _acc ->
          {node, resolve_status(status_arg)}

        # conn |> put_status(:created) — piped 1-arg call
        {:put_status, _, [status_arg]} = node, _acc when is_atom(status_arg) ->
          {node, resolve_status(status_arg)}

        # Plug.Conn.put_status(conn, :created) — module 2-arg call
        {{:., _, [{:__aliases__, _, _}, :put_status]}, _, [_, status_arg]} = node, _acc ->
          {node, resolve_status(status_arg)}

        # conn |> Plug.Conn.put_status(:created) — piped module 1-arg call
        {{:., _, [{:__aliases__, _, _}, :put_status]}, _, [status_arg]} = node, _acc ->
          {node, resolve_status(status_arg)}

        # send_resp(conn, :no_content, "") — direct 3-arg call
        {:send_resp, _, [_, status_arg, _]} = node, _acc ->
          {node, resolve_status(status_arg)}

        # conn |> send_resp(:no_content, "") — piped 2-arg call
        {:send_resp, _, [status_arg, _]} = node, _acc ->
          {node, resolve_status(status_arg)}

        # Plug.Conn.send_resp(conn, :no_content, "") — module 3-arg call
        {{:., _, [{:__aliases__, _, _}, :send_resp]}, _, [_, status_arg, _]} = node, _acc ->
          {node, resolve_status(status_arg)}

        # conn |> Plug.Conn.send_resp(:no_content, "") — piped module 2-arg call
        {{:., _, [{:__aliases__, _, _}, :send_resp]}, _, [status_arg, _]} = node, _acc ->
          {node, resolve_status(status_arg)}

        node, acc ->
          {node, acc}
      end)

    status
  end

  defp resolve_status(code) when is_integer(code), do: code
  defp resolve_status(atom) when is_atom(atom), do: Map.get(@status_codes, atom)
  defp resolve_status(_), do: nil
end
