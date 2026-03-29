defmodule Livellm.Chats.Message do
  @moduledoc """
  Schema for chat messages.

  Assistant messages persist two usage views on purpose:

  * the top-level usage fields store the aggregate totals for the full assistant turn
  * `usage_breakdown` stores the per-iteration usage trace that produced those totals

  The field overlap with `UsageBreakdownEntry` is intentional. The aggregate fields make
  chat-level reads and UI rendering simple, while the embedded breakdown preserves
  iteration-by-iteration detail for tool-call loops and debugging.
  """
  use Ecto.Schema

  import Ecto.Changeset

  alias Livellm.Chats.Chat
  alias Livellm.Chats.Message.ReasoningStep
  alias Livellm.Chats.Message.UsageBreakdownEntry

  @type t :: %__MODULE__{
          id: integer() | nil,
          role: String.t(),
          content: String.t() | nil,
          reasoning: String.t() | nil,
          reasoning_steps: list(ReasoningStep.t()),
          reasoning_details: list(map()) | nil,
          raw_response: map() | nil,
          provider_messages: map() | nil,
          input_tokens: integer() | nil,
          output_tokens: integer() | nil,
          total_tokens: integer() | nil,
          cached_tokens: integer() | nil,
          reasoning_tokens: integer() | nil,
          input_cost: Decimal.t() | nil,
          output_cost: Decimal.t() | nil,
          total_cost: Decimal.t() | nil,
          cost_currency: String.t() | nil,
          provider_name: String.t() | nil,
          provider_model: String.t() | nil,
          provider_response_id: String.t() | nil,
          usage_breakdown: list(UsageBreakdownEntry.t()),
          tool_calls: list(map()) | nil,
          chat_id: integer() | nil,
          chat: Chat.t() | nil,
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  schema "messages" do
    field :role, :string
    field :content, :string
    field :reasoning, :string
    field :reasoning_steps, {:array, :map}, default: []
    field :reasoning_details, {:array, :map}
    field :raw_response, :map
    field :provider_messages, :map
    field :input_tokens, :integer
    field :output_tokens, :integer
    field :total_tokens, :integer
    field :cached_tokens, :integer
    field :reasoning_tokens, :integer
    field :input_cost, :decimal
    field :output_cost, :decimal
    field :total_cost, :decimal
    field :cost_currency, :string
    field :provider_name, :string
    field :provider_model, :string
    field :provider_response_id, :string
    # Stores the per-iteration trace; the top-level usage fields remain the turn totals.
    embeds_many :usage_breakdown, UsageBreakdownEntry, on_replace: :delete
    field :tool_calls, {:array, :map}
    belongs_to :chat, Chat

    timestamps(type: :utc_datetime)
  end

  @required [:role]
  @optional [
    :content,
    :reasoning,
    :reasoning_steps,
    :reasoning_details,
    :raw_response,
    :provider_messages,
    :input_tokens,
    :output_tokens,
    :total_tokens,
    :cached_tokens,
    :reasoning_tokens,
    :input_cost,
    :output_cost,
    :total_cost,
    :cost_currency,
    :provider_name,
    :provider_model,
    :provider_response_id,
    :tool_calls
  ]

  @doc false
  def changeset(message, attrs) do
    message
    |> cast(attrs, @required ++ @optional)
    |> cast_embed(:usage_breakdown)
    |> validate_required(@required)
    |> validate_inclusion(:role, ["user", "assistant", "system", "tool"])
    |> assoc_constraint(:chat)
  end
end
