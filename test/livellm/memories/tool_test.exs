defmodule Livellm.Memories.ToolTest do
  use Livellm.DataCase, async: true

  alias Livellm.Memories
  alias Livellm.Memories.Tool

  test "definitions include multiget and delete in the action enum" do
    [definition] = Tool.definitions()

    assert get_in(definition.schema, [:properties, :action, :enum]) == [
             "list",
             "get",
             "multiget",
             "search",
             "write",
             "delete"
           ]

    assert definition.schema.required == ["action", "id", "ids", "data", "title"]
    assert get_in(definition.schema, [:properties, :id, :type]) == ["integer", "null"]
    assert get_in(definition.schema, [:properties, :ids, :type]) == ["array", "null"]
    assert get_in(definition.schema, [:properties, :ids, :items, :type]) == "integer"
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

  test "multiget returns multiple memories in the requested order" do
    {:ok, first} = Memories.create_memory(%{title: "First", content: "One"})
    {:ok, second} = Memories.create_memory(%{title: "Second", content: "Two"})

    assert Tool.manage_memory(%{"action" => "multiget", "ids" => [second.id, first.id]}) ==
             """
             ID #{second.id}
             Title: Second
             Content: Two

             ID #{first.id}
             Title: First
             Content: One
             """
             |> String.trim()
  end

  test "multiget deduplicates ids" do
    {:ok, memory} = Memories.create_memory(%{title: "First", content: "One"})

    assert Tool.manage_memory(%{"action" => "multiget", "ids" => [memory.id, memory.id]}) ==
             """
             ID #{memory.id}
             Title: First
             Content: One
             """
             |> String.trim()
  end

  test "multiget returns found memories and missing ids" do
    {:ok, memory} = Memories.create_memory(%{title: "First", content: "One"})

    assert Tool.manage_memory(%{"action" => "multiget", "ids" => [memory.id, 999_999]}) ==
             """
             ID #{memory.id}
             Title: First
             Content: One

             Missing IDs: 999999
             """
             |> String.trim()
  end

  test "multiget returns missing ids when none are found" do
    assert Tool.manage_memory(%{"action" => "multiget", "ids" => [999_999, 999_998]}) ==
             "Missing IDs: 999999, 999998"
  end

  test "multiget validates ids" do
    assert Tool.manage_memory(%{"action" => "multiget"}) ==
             "Error: multiget requires an ids field with a non-empty list of integer ids."

    assert Tool.manage_memory(%{"action" => "multiget", "ids" => []}) ==
             "Error: multiget requires an ids field with a non-empty list of integer ids."

    assert Tool.manage_memory(%{"action" => "multiget", "ids" => [1, "2"]}) ==
             "Error: multiget requires an ids field with a non-empty list of integer ids."
  end
end
