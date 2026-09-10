defmodule PhoenixSpec.GenTaskTest do
  use ExUnit.Case

  test "forwards CLI descriptions into JSON and YAML output" do
    for format <- ["json", "yaml"] do
      output =
        Path.join(
          System.tmp_dir!(),
          "phoenix_spec_cli_#{System.unique_integer([:positive])}.#{format}"
        )

      on_exit(fn -> File.rm(output) end)

      Mix.Tasks.PhoenixSpec.Gen.run([
        "--router",
        "TestAppWeb.Router",
        "--output",
        output,
        "--format",
        format,
        "--description",
        "CLI API documentation"
      ])

      content = File.read!(output)
      assert content =~ "CLI API documentation"

      if format == "json",
        do: assert(Jason.decode!(content)["info"]["description"] == "CLI API documentation")
    end
  end
end
