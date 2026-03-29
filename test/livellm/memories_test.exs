defmodule Livellm.MemoriesTest do
  use Livellm.DataCase, async: true

  alias Livellm.Memories

  test "get_memories/1 preserves the requested order and skips missing ids" do
    {:ok, first} = Memories.create_memory(%{title: "First", content: "One"})
    {:ok, second} = Memories.create_memory(%{title: "Second", content: "Two"})
    {:ok, third} = Memories.create_memory(%{title: "Third", content: "Three"})

    memories = Memories.get_memories([third.id, first.id, 999_999, second.id, first.id])

    assert Enum.map(memories, & &1.id) == [third.id, first.id, second.id]
  end
end
