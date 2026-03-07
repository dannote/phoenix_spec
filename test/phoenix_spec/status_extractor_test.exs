defmodule PhoenixSpec.StatusExtractorTest do
  use ExUnit.Case, async: true

  alias PhoenixSpec.StatusExtractor

  test "detects put_status(:created) in create action" do
    statuses = StatusExtractor.extract(TestAppWeb.PostController)
    assert statuses[:create] == 201
  end

  test "detects send_resp(conn, :no_content) in delete action" do
    statuses = StatusExtractor.extract(TestAppWeb.PostController)
    assert statuses[:delete] == 204
  end

  test "returns empty map for controllers without status calls" do
    statuses = StatusExtractor.extract(TestAppWeb.UserController)
    assert statuses == %{}
  end
end
