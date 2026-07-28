defmodule PhoenixSpec.DiscoveryTest do
  use ExUnit.Case, async: true

  alias PhoenixSpec.Discovery

  test "prefers conventional JSON modules" do
    assert Discovery.controller_to_json_view(TestAppWeb.PostController) == TestAppWeb.PostJSON
  end

  test "uses controllers that render JSON inline as response modules" do
    response_modules = Discovery.json_views_from_router(TestAppWeb.Router)

    assert TestAppWeb.InlinePostController in response_modules
  end
end
