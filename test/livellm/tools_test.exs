defmodule Livellm.ToolsTest do
  use ExUnit.Case, async: true

  alias Livellm.Tools
  alias Livellm.Tools.Markdown

  test "catalog and definitions are loaded from markdown files" do
    assert Enum.map(Tools.catalog(), & &1.name) == ["memory", "request"]

    assert Enum.map(Tools.definitions(), & &1.name) == ["memory", "request"]
  end

  test "enabled_definitions/1 filters by selected names" do
    assert Enum.map(Tools.enabled_definitions(["request"]), & &1.name) == ["request"]
  end

  test "markdown parser requires mf.function to match an existing exported /1 function" do
    contents = """
    ---
    name: bad_tool
    mf:
      module: Livellm.Tools.Http
      function: definitely_missing
    schema:
      type: object
      properties: {}
      required: []
      additionalProperties: false
    ---
    Broken tool.
    """

    assert_raise ArgumentError, ~r/existing Livellm.Tools.Http export/, fn ->
      Markdown.parse!(contents, "bad_tool.md")
    end
  end
end
