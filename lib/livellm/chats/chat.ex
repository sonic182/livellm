defmodule Livellm.Chats.Chat do
  use Ecto.Schema
  import Ecto.Changeset

  alias Livellm.Chats.Message
  alias Livellm.Config.ProviderConfig

  schema "chats" do
    field :title, :string
    field :model, :string
    field :reasoning_effort, :string
    belongs_to :provider_config, ProviderConfig
    has_many :messages, Message

    timestamps(type: :utc_datetime)
  end

  @required [:title, :model]
  @valid_efforts ~w(xhigh high medium low minimal none)
  @optional [:reasoning_effort, :provider_config_id]

  @doc false
  def changeset(chat, attrs) do
    chat
    |> cast(attrs, @required ++ @optional)
    |> validate_required(@required)
    |> validate_inclusion(:reasoning_effort, @valid_efforts)
  end
end
