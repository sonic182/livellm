defmodule Livellm.Chats.Message.UsageBreakdownEntry do
  @moduledoc """
  Embedded usage and cost data for a single LLM iteration within a chat turn.
  """

  use Ecto.Schema

  import Ecto.Changeset

  @primary_key false

  @type t :: %__MODULE__{
          iteration: integer() | nil,
          result_type: String.t() | nil,
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
          provider_response_id: String.t() | nil
        }

  embedded_schema do
    field :iteration, :integer
    field :result_type, :string
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
  end

  @doc false
  def changeset(entry, attrs) do
    entry
    |> cast(attrs, [
      :iteration,
      :result_type,
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
      :provider_response_id
    ])
    |> validate_required([:iteration, :result_type])
    |> validate_inclusion(:result_type, ["tool_calls", "final"])
  end
end
