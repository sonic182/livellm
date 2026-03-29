defmodule Livellm.Memories.Memory do
  use Ecto.Schema
  import Ecto.Changeset

  schema "user_memories" do
    field :title, :string
    field :content, :string

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(memory, attrs) do
    memory
    |> cast(attrs, [:title, :content])
    |> validate_required([:title, :content])
  end
end
