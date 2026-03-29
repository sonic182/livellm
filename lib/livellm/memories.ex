defmodule Livellm.Memories do
  @moduledoc """
  Context for managing user memories.
  """

  import Ecto.Query

  alias Livellm.Memories.Memory
  alias Livellm.Repo

  @doc "Returns all memories ordered by insertion date."
  def list_memories do
    Repo.all(from m in Memory, order_by: [asc: m.inserted_at])
  end

  @doc "Gets a single memory by id, raises if not found."
  def get_memory!(id), do: Repo.get!(Memory, id)

  @doc "Creates a memory."
  def create_memory(attrs \\ %{}) do
    %Memory{}
    |> Memory.changeset(attrs)
    |> Repo.insert()
  end

  @doc "Deletes a memory."
  def delete_memory(%Memory{} = memory) do
    Repo.delete(memory)
  end
end
