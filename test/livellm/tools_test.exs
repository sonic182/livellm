defmodule Livellm.ToolsTest do
  use ExUnit.Case, async: true

  alias Livellm.Tools

  test "catalog and definitions are loaded from markdown files" do
    assert Enum.map(Tools.catalog(), & &1.name) == ["memory", "request"]

    assert Enum.map(Tools.definitions(), & &1.name) == ["memory", "request"]
  end

  test "enabled_definitions/1 filters by selected names" do
    assert Enum.map(Tools.enabled_definitions(["request"]), & &1.name) == ["request"]
  end
end
