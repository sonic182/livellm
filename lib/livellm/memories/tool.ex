defmodule Livellm.Memories.Tool do
  @moduledoc """
  Defines LlmComposer.Function tools for user memories.

  Exposes a single `memory` tool that accepts {action, data, title?} and
  dispatches to list/get/search/write operations.
  """

  alias Livellm.Memories

  @doc "Returns the list of LlmComposer.Function definitions for memory tools."
  def definitions do
    [
      %LlmComposer.Function{
        name: "memory",
        description: "Manage user memories: list all, get by id, search by text, or write new.",
        mf: {__MODULE__, :manage_memory},
        schema: %{
          type: "object",
          properties: %{
            action: %{
              type: "string",
              enum: ["list", "get", "search", "write"],
              description: "list: all memories; get: one by id; search: by text; write: save new."
            },
            data: %{
              type: ["string", "null"],
              description:
                "Omit for list. Integer id string for get. Search text for search. Content to save for write."
            },
            title: %{
              type: ["string", "null"],
              description:
                "Required for write: a short title for the memory. Ignored for other actions."
            }
          },
          additionalProperties: false,
          required: ["action", "title", "data"]
        }
      }
    ]
  end

  @doc false
  def manage_memory(%{"action" => "list"}) do
    format_list(Memories.list_memories())
  end

  def manage_memory(%{"action" => "get", "data" => id}) do
    case Memories.get_memory(String.to_integer(id)) do
      nil -> "Not found."
      memory -> format_one(memory)
    end
  end

  def manage_memory(%{"action" => "search", "data" => text}) do
    format_list(Memories.search_memories(text))
  end

  def manage_memory(%{"action" => "write", "data" => content, "title" => title})
      when is_binary(title) and title != "" do
    case Memories.create_memory(%{title: title, content: content}) do
      {:ok, memory} -> "Saved memory ID #{memory.id}."
      {:error, _} -> "Error: could not save memory."
    end
  end

  def manage_memory(%{"action" => "write"}) do
    "Error: write requires both data (content) and title fields."
  end

  def manage_memory(_args) do
    "Unknown action or missing required data."
  end

  defp format_list([]), do: "No memories."

  defp format_list(memories) do
    Enum.map_join(memories, "\n", fn m -> "ID #{m.id} — #{m.title}" end)
  end

  defp format_one(m), do: "Title: #{m.title}\n\nContent: #{m.content}"
end
