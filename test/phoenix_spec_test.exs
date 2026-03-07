defmodule PhoenixSpecTest do
  use ExUnit.Case
  doctest PhoenixSpec

  test "greets the world" do
    assert PhoenixSpec.hello() == :world
  end
end
