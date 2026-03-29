defmodule Livellm.Memories.Tool do
  @moduledoc """
  Runtime implementation for the markdown-defined `memory` tool.
  """

  alias Livellm.Memories

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

  def manage_memory(%{"action" => "multiget", "ids" => ids}) when is_list(ids) do
    case normalize_ids(ids) do
      {:ok, normalized_ids} ->
        memories = Memories.get_memories(normalized_ids)
        found_ids = MapSet.new(memories, & &1.id)

        missing_ids =
          Enum.reject(normalized_ids, fn id ->
            MapSet.member?(found_ids, id)
          end)

        format_multiget(memories, missing_ids)

      :error ->
        "Error: multiget requires an ids field with a non-empty list of integer ids."
    end
  end

  def manage_memory(%{"action" => "multiget"}) do
    "Error: multiget requires an ids field with a non-empty list of integer ids."
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

  def manage_memory(%{"action" => "delete", "id" => id}) when is_integer(id) do
    case Memories.get_memory(id) do
      nil ->
        "Not found."

      memory ->
        case Memories.delete_memory(memory) do
          {:ok, deleted} -> "Deleted memory ID #{deleted.id}."
          {:error, _} -> "Error: could not delete memory."
        end
    end
  end

  def manage_memory(%{"action" => "delete"}) do
    "Error: delete requires an integer id field."
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

  defp format_multiget(memories, missing_ids) do
    sections =
      Enum.map(memories, fn memory ->
        "ID #{memory.id}\nTitle: #{memory.title}\nContent: #{memory.content}"
      end)

    missing_section =
      case missing_ids do
        [] -> []
        ids -> ["Missing IDs: " <> Enum.map_join(ids, ", ", &to_string/1)]
      end

    case sections ++ missing_section do
      [] -> "No memories."
      parts -> Enum.join(parts, "\n\n")
    end
  end

  defp format_one(m), do: "Title: #{m.title}\n\nContent: #{m.content}"

  defp normalize_ids(ids) do
    cond do
      ids == [] ->
        :error

      Enum.all?(ids, &is_integer/1) ->
        {:ok, Enum.uniq(ids)}

      true ->
        :error
    end
  end
end
