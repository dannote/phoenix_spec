defmodule PhoenixSpec.CompilerTest do
  use ExUnit.Case

  alias PhoenixSpec.Compiler

  setup do
    output = Path.join(System.tmp_dir!(), "phoenix_spec_test_#{:rand.uniform(100_000)}.json")

    Application.put_all_env(
      phoenix_spec: [
        router: TestAppWeb.Router,
        output: output,
        format: "json",
        title: "Test API",
        version: "1.0.0"
      ]
    )

    Compiler.clean()

    on_exit(fn ->
      File.rm(output)
      Compiler.clean()
      Application.delete_env(:phoenix_spec, :router)
      Application.delete_env(:phoenix_spec, :output)
      Application.delete_env(:phoenix_spec, :format)
      Application.delete_env(:phoenix_spec, :title)
      Application.delete_env(:phoenix_spec, :version)
    end)

    %{output: output}
  end

  test "generates spec file on first run", %{output: output} do
    assert {:ok, []} = Compiler.run([])
    assert File.exists?(output)

    spec = output |> File.read!() |> Jason.decode!()
    assert spec["openapi"] == "3.1.0"
    assert spec["info"]["title"] == "Test API"
  end

  test "second run returns :noop when nothing changed", %{output: output} do
    assert {:ok, []} = Compiler.run([])
    assert File.exists?(output)

    assert {:noop, []} = Compiler.run([])
  end

  test "returns :noop when no router configured" do
    Application.delete_env(:phoenix_spec, :router)
    assert {:noop, []} = Compiler.run([])
  end

  test "supports multiple outputs" do
    ts_output = Path.join(System.tmp_dir!(), "phoenix_spec_test_#{:rand.uniform(100_000)}.d.ts")

    json_output =
      Path.join(System.tmp_dir!(), "phoenix_spec_test_#{:rand.uniform(100_000)}.json")

    Application.put_env(:phoenix_spec, :outputs, [
      {json_output, "json"},
      {ts_output, "ts"}
    ])

    on_exit(fn ->
      File.rm(ts_output)
      File.rm(json_output)
      Application.delete_env(:phoenix_spec, :outputs)
    end)

    assert {:ok, []} = Compiler.run([])
    assert File.exists?(json_output)
    assert File.exists?(ts_output)

    ts_content = File.read!(ts_output)
    assert ts_content =~ "export interface Post"
  end
end
