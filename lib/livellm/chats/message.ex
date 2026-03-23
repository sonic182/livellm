defmodule Livellm.Chats.Message do
  use Ecto.Schema
  import Ecto.Changeset

  alias Livellm.Chats.Chat

  schema "messages" do
    field :role, :string
    field :content, :string
    field :reasoning, :string
    field :reasoning_details, {:array, :map}
    field :raw_response, :map
    field :provider_messages, :map
    field :input_tokens, :integer
    field :output_tokens, :integer
    field :total_tokens, :integer
    field :reasoning_tokens, :integer
    field :input_cost, :decimal
    field :output_cost, :decimal
    field :total_cost, :decimal
    field :cost_currency, :string
    field :provider_name, :string
    field :provider_model, :string
    belongs_to :chat, Chat

    timestamps(type: :utc_datetime)
  end

  @required [:role]
  @optional [
    :content,
    :reasoning,
    :reasoning_details,
    :raw_response,
    :provider_messages,
    :input_tokens,
    :output_tokens,
    :total_tokens,
    :reasoning_tokens,
    :input_cost,
    :output_cost,
    :total_cost,
    :cost_currency,
    :provider_name,
    :provider_model
  ]

  @doc false
  def changeset(message, attrs) do
    message
    |> cast(attrs, @required ++ @optional)
    |> validate_required(@required)
    |> validate_inclusion(:role, ["user", "assistant", "system", "tool"])
    |> assoc_constraint(:chat)
  end
end
