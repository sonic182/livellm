defmodule Livellm.Usage do
  @moduledoc """
  Utilities for normalizing and aggregating LLM usage and cost data.
  """

  alias Decimal

  @type chat_metrics :: %{
          input_tokens: non_neg_integer(),
          output_tokens: non_neg_integer(),
          total_tokens: non_neg_integer(),
          total_cost: Decimal.t() | nil,
          currency: String.t() | nil,
          cost_tracked?: boolean()
        }

  @spec empty_chat_metrics() :: chat_metrics()
  def empty_chat_metrics do
    %{
      input_tokens: 0,
      output_tokens: 0,
      total_tokens: 0,
      total_cost: nil,
      currency: nil,
      cost_tracked?: false
    }
  end

  @spec aggregate_chat_metrics([map()]) :: chat_metrics()
  def aggregate_chat_metrics(messages) do
    Enum.reduce(messages, empty_chat_metrics(), &merge_chat_metrics(&2, &1))
  end

  @spec merge_chat_metrics(chat_metrics(), map()) :: chat_metrics()
  def merge_chat_metrics(metrics, %{role: "assistant"} = message) do
    metrics =
      %{
        metrics
        | input_tokens: metrics.input_tokens + (message.input_tokens || 0),
          output_tokens: metrics.output_tokens + (message.output_tokens || 0),
          total_tokens: metrics.total_tokens + (message.total_tokens || 0)
      }

    case message.total_cost do
      %Decimal{} = total_cost ->
        %{
          metrics
          | total_cost: Decimal.add(metrics.total_cost || Decimal.new(0), total_cost),
            currency: metrics.currency || message.cost_currency,
            cost_tracked?: true
        }

      _ ->
        metrics
    end
  end

  def merge_chat_metrics(metrics, _message), do: metrics

  @spec cost_tracking_attrs(LlmComposer.LlmResponse.t()) :: map()
  def cost_tracking_attrs(llm_response) do
    cost_info = llm_response.cost_info
    input_tokens = token_value(cost_info, :input_tokens, llm_response.input_tokens)
    output_tokens = token_value(cost_info, :output_tokens, llm_response.output_tokens)

    %{
      input_tokens: input_tokens,
      output_tokens: output_tokens,
      total_tokens: token_total(cost_info, input_tokens, output_tokens),
      input_cost: cost_value(cost_info, :input_cost),
      output_cost: cost_value(cost_info, :output_cost),
      total_cost: cost_value(cost_info, :total_cost),
      cost_currency: cost_value(cost_info, :currency),
      provider_name: provider_name(cost_info, llm_response.provider),
      provider_model: provider_model(cost_info, llm_response.raw)
    }
  end

  @spec format_total_tokens(chat_metrics()) :: String.t() | nil
  def format_total_tokens(%{total_tokens: total_tokens}) when total_tokens > 0 do
    "#{total_tokens} tokens"
  end

  def format_total_tokens(_metrics), do: nil

  @spec format_total_cost(chat_metrics()) :: String.t() | nil
  def format_total_cost(%{cost_tracked?: true, total_cost: %Decimal{} = total_cost} = metrics) do
    amount =
      total_cost
      |> Decimal.round(6)
      |> Decimal.normalize()
      |> Decimal.to_string(:normal)

    case metrics.currency do
      nil -> "$#{amount}"
      "USD" -> "$#{amount}"
      currency -> "#{currency} #{amount}"
    end
  end

  def format_total_cost(_metrics), do: nil

  defp token_value(nil, _field, fallback), do: fallback
  defp token_value(cost_info, field, _fallback), do: Map.get(cost_info, field)

  defp token_total(nil, nil, nil), do: nil

  defp token_total(nil, input_tokens, output_tokens),
    do: (input_tokens || 0) + (output_tokens || 0)

  defp token_total(cost_info, _input_tokens, _output_tokens), do: cost_info.total_tokens

  defp cost_value(nil, _field), do: nil
  defp cost_value(cost_info, field), do: Map.get(cost_info, field)

  defp provider_name(nil, provider) when is_atom(provider), do: Atom.to_string(provider)
  defp provider_name(nil, provider), do: provider
  defp provider_name(cost_info, _provider), do: to_string(cost_info.provider_name)

  defp provider_model(nil, %{"model" => model}) when is_binary(model), do: model
  defp provider_model(nil, _raw), do: nil
  defp provider_model(cost_info, _raw), do: cost_info.provider_model
end
