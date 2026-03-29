defmodule Livellm.Memories.ToolTest do
  use Livellm.DataCase, async: true

  alias Livellm.Memories
  alias Livellm.Memories.Tool

  test "definitions include delete in the action enum" do
    [definition] = Tool.definitions()

    assert get_in(definition.schema, [:properties, :action, :enum]) == [
             "list",
             "get",
             "search",
             "write",
             "delete"
           ]
  end

  test "delete removes an existing memory" do
    {:ok, memory} =
      Memories.create_memory(%{
        title: "Temporary",
        content: "Delete me"
      })

    assert Tool.manage_memory(%{"action" => "delete", "id" => memory.id}) ==
             "Deleted memory ID #{memory.id}."

    assert Memories.get_memory(memory.id) == nil
  end

  test "delete without id returns a validation error" do
    assert Tool.manage_memory(%{"action" => "delete"}) ==
             "Error: delete requires an integer id field."
  end

  test "delete returns not found for a missing memory" do
    assert Tool.manage_memory(%{"action" => "delete", "id" => 999_999}) == "Not found."
  end
end
