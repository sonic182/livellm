defmodule Livellm.Memories.Tool do
  @moduledoc """
  Defines LlmComposer.Function tools for user memories.

  Exposes a single `memory` tool that accepts {action, id?, data?, title?} and
  dispatches to list/get/search/write operations. Write with an id updates the
  existing record; write without an id creates a new one.
  """

  alias Livellm.Memories

  @doc "Returns the list of LlmComposer.Function definitions for memory tools."
  def definitions do
    [
      %LlmComposer.Function{
        name: "memory",
        description:
          "Manage user memories: list all, get by id, search by text, or write (create/update).",
        mf: {__MODULE__, :manage_memory},
        schema: %{
          type: "object",
          properties: %{
            action: %{
              type: "string",
              enum: ["list", "get", "search", "write"],
              description:
                "list: all memories; get: one by id; search: by text; write: save new or update existing."
            },
            id: %{
              type: ["number", "null"],
              description:
                "Id of the memory to retrieve (get) or update (write). Omit or null when creating new."
            },
            data: %{
              type: ["string", "null"],
              description:
                "Search text for search. Content to save for write. Omit for list and get."
            },
            title: %{
              type: ["string", "null"],
              description:
                "Title for write. Required when creating; optional when updating (omit to keep existing title)."
            }
          },
          additionalProperties: false,
          required: ["action"]
        }
      }
    ]
  end

  @doc false
  def manage_memory(%{"action" => "list"}) do
    format_list(Memories.list_memories())
  end

  def manage_memory(%{"action" => "get", "id" => id}) when is_integer(id) do
    case Memories.get_memory(id) do
      nil -> "Not found."
      memory -> format_one(memory)
    end
  end

  def manage_memory(%{"action" => "get"}) do
    "Error: get requires an integer id field."
  end

  def manage_memory(%{"action" => "search", "data" => text}) when is_binary(text) do
    format_list(Memories.search_memories(text))
  end

  def manage_memory(%{"action" => "search"}) do
    "Error: search requires a data field with the search text."
  end

  def manage_memory(%{"action" => "write", "id" => id} = args) when is_integer(id) do
    case Memories.get_memory(id) do
      nil ->
        "Not found."

      memory ->
        attrs =
          %{}
          |> maybe_put(:title, args["title"])
          |> maybe_put(:content, args["data"])

        case Memories.update_memory(memory, attrs) do
          {:ok, updated} -> "Updated memory ID #{updated.id}."
          {:error, _} -> "Error: could not update memory."
        end
    end
  end

  def manage_memory(%{"action" => "write", "data" => content, "title" => title})
      when is_binary(title) and title != "" and is_binary(content) do
    case Memories.create_memory(%{title: title, content: content}) do
      {:ok, memory} -> "Saved memory ID #{memory.id}."
      {:error, _} -> "Error: could not save memory."
    end
  end

  def manage_memory(%{"action" => "write"}) do
    "Error: write requires data (content) and title to create, or id to update."
  end

  def manage_memory(_args) do
    "Unknown action or missing required data."
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp format_list([]), do: "No memories."

  defp format_list(memories) do
    Enum.map_join(memories, "\n", fn m -> "ID #{m.id} — #{m.title}" end)
  end

  defp format_one(m), do: "Title: #{m.title}\n\nContent: #{m.content}"
end
