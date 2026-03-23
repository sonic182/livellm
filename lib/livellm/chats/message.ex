defmodule Livellm.Chats.Message do
  use Ecto.Schema
  import Ecto.Changeset

  alias Livellm.Chats.Chat

  schema "messages" do
    field :role, :string
    field :content, :string
    field :reasoning, :string
    field :reasoning_details, :map
    field :raw_response, :map
    field :provider_messages, :map
    belongs_to :chat, Chat

    timestamps(type: :utc_datetime)
  end

  @required [:role]
  @optional [:content, :reasoning, :reasoning_details, :raw_response, :provider_messages]

  @doc false
  def changeset(message, attrs) do
    message
    |> cast(attrs, @required ++ @optional)
    |> validate_required(@required)
    |> validate_inclusion(:role, ["user", "assistant", "system", "tool"])
    |> assoc_constraint(:chat)
  end
end
