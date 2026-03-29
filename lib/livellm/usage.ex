defmodule Livellm.Usage do
  @moduledoc """
  Utilities for normalizing and aggregating LLM usage and cost data.
  """

  alias Decimal
  alias Livellm.Chats.Message.UsageBreakdownEntry
  alias LlmComposer.CostInfo

  @type chat_metrics :: %{
          input_tokens: non_neg_integer(),
          output_tokens: non_neg_integer(),
          total_tokens: non_neg_integer(),
          cached_tokens: non_neg_integer(),
          reasoning_tokens: non_neg_integer(),
          input_cost: Decimal.t() | nil,
          output_cost: Decimal.t() | nil,
          total_cost: Decimal.t() | nil,
          currency: String.t() | nil,
          cost_tracked?: boolean()
        }

  @type usage_breakdown_entry :: UsageBreakdownEntry.t()

  @spec empty_chat_metrics() :: chat_metrics()
  def empty_chat_metrics do
    %{
      input_tokens: 0,
      output_tokens: 0,
      total_tokens: 0,
      cached_tokens: 0,
      reasoning_tokens: 0,
      input_cost: nil,
      output_cost: nil,
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
    metrics = merge_assistant_tokens(metrics, message)

    case message.total_cost do
      %Decimal{} = total_cost ->
        %{
          metrics
          | total_cost: Decimal.add(metrics.total_cost || Decimal.new(0), total_cost),
            input_cost: add_cost(metrics.input_cost, Map.get(message, :input_cost)),
            output_cost: add_cost(metrics.output_cost, Map.get(message, :output_cost)),
            currency: metrics.currency || Map.get(message, :cost_currency),
            cost_tracked?: true
        }

      _ ->
        metrics
    end
  end

  def merge_chat_metrics(metrics, _message), do: metrics

  defp merge_assistant_tokens(metrics, message) do
    %{
      metrics
      | input_tokens: metrics.input_tokens + (message.input_tokens || 0),
        output_tokens: metrics.output_tokens + (message.output_tokens || 0),
        total_tokens: metrics.total_tokens + (message.total_tokens || 0),
        cached_tokens: metrics.cached_tokens + (message.cached_tokens || 0),
        reasoning_tokens: metrics.reasoning_tokens + (message.reasoning_tokens || 0)
    }
  end

  @spec cost_tracking_attrs(LlmComposer.LlmResponse.t()) :: map()
  def cost_tracking_attrs(llm_response) do
    cost_info = llm_response.cost_info
    input_tokens = token_value(cost_info, :input_tokens, llm_response.input_tokens)
    output_tokens = token_value(cost_info, :output_tokens, llm_response.output_tokens)

    %{
      input_tokens: input_tokens,
      output_tokens: output_tokens,
      total_tokens: token_total(cost_info, input_tokens, output_tokens),
      cached_tokens: cached_tokens(cost_info, llm_response.raw, llm_response.cached_tokens),
      reasoning_tokens: reasoning_tokens(llm_response),
      input_cost: cost_value(cost_info, :input_cost),
      output_cost: cost_value(cost_info, :output_cost),
      total_cost: cost_value(cost_info, :total_cost),
      cost_currency: cost_value(cost_info, :currency),
      provider_name: provider_name(cost_info, llm_response.provider),
      provider_model: provider_model(cost_info, llm_response),
      provider_response_id: provider_response_id(llm_response)
    }
  end

  @spec stream_chunk_attrs(LlmComposer.StreamChunk.t() | nil) :: map()
  def stream_chunk_attrs(nil), do: %{}

  def stream_chunk_attrs(chunk) do
    cost_info = chunk.cost_info
    usage = chunk.usage
    input_tokens = usage && usage.input_tokens
    output_tokens = usage && usage.output_tokens

    %{
      input_tokens: token_value(cost_info, :input_tokens, input_tokens),
      output_tokens: token_value(cost_info, :output_tokens, output_tokens),
      total_tokens: token_total(cost_info, input_tokens, output_tokens),
      cached_tokens: cached_tokens(cost_info, chunk.raw, usage && Map.get(usage, :cached_tokens)),
      reasoning_tokens: usage && Map.get(usage, :reasoning_tokens),
      input_cost: cost_value(cost_info, :input_cost),
      output_cost: cost_value(cost_info, :output_cost),
      total_cost: cost_value(cost_info, :total_cost),
      cost_currency: cost_value(cost_info, :currency),
      provider_name: provider_name(cost_info, chunk.provider),
      provider_model: provider_model(cost_info, chunk),
      provider_response_id: provider_response_id(chunk)
    }
  end

  @spec usage_breakdown_entry_from_response(
          LlmComposer.LlmResponse.t(),
          pos_integer(),
          String.t()
        ) ::
          usage_breakdown_entry()
  def usage_breakdown_entry_from_response(llm_response, iteration, result_type) do
    llm_response
    |> cost_tracking_attrs()
    |> Map.put(:iteration, iteration)
    |> Map.put(:result_type, result_type)
  end

  @spec usage_breakdown_entry_from_chunk(
          LlmComposer.StreamChunk.t() | nil,
          pos_integer(),
          String.t()
        ) ::
          usage_breakdown_entry()
  def usage_breakdown_entry_from_chunk(chunk, iteration, result_type) do
    chunk
    |> stream_chunk_attrs()
    |> Map.put(:iteration, iteration)
    |> Map.put(:result_type, result_type)
  end

  @spec aggregate_usage_breakdown([usage_breakdown_entry()]) :: map()
  def aggregate_usage_breakdown(entries) when is_list(entries) do
    Enum.reduce(entries, empty_usage_totals(), &merge_usage_entry/2)
  end

  @spec format_total_tokens(chat_metrics()) :: String.t() | nil
  def format_total_tokens(%{total_tokens: total_tokens}) when total_tokens > 0 do
    "#{total_tokens} tokens"
  end

  def format_total_tokens(_metrics), do: nil

  @spec format_reasoning_tokens(chat_metrics()) :: String.t() | nil
  def format_reasoning_tokens(%{reasoning_tokens: reasoning_tokens}) when reasoning_tokens > 0 do
    "#{reasoning_tokens} reasoning"
  end

  def format_reasoning_tokens(_metrics), do: nil

  @spec format_cached_tokens(chat_metrics()) :: String.t() | nil
  def format_cached_tokens(%{cached_tokens: cached_tokens}) when cached_tokens > 0 do
    "#{cached_tokens} cached"
  end

  def format_cached_tokens(_metrics), do: nil

  @spec format_total_cost(chat_metrics()) :: String.t() | nil
  def format_total_cost(%{cost_tracked?: true, total_cost: %Decimal{} = total_cost} = metrics) do
    format_cost(total_cost, metrics.currency)
  end

  def format_total_cost(_metrics), do: nil

  @spec format_input_cost(chat_metrics()) :: String.t() | nil
  def format_input_cost(%{cost_tracked?: true, input_cost: %Decimal{} = input_cost} = metrics) do
    format_cost(input_cost, metrics.currency)
  end

  def format_input_cost(_metrics), do: nil

  @spec format_output_cost(chat_metrics()) :: String.t() | nil
  def format_output_cost(%{cost_tracked?: true, output_cost: %Decimal{} = output_cost} = metrics) do
    format_cost(output_cost, metrics.currency)
  end

  def format_output_cost(_metrics), do: nil

  @spec uncached_input_tokens(chat_metrics()) :: non_neg_integer()
  def uncached_input_tokens(%{input_tokens: input_tokens, cached_tokens: cached_tokens}) do
    max(input_tokens - cached_tokens, 0)
  end

  @spec token_breakdown(chat_metrics()) :: map()
  def token_breakdown(metrics) do
    %{
      input_tokens: metrics.input_tokens,
      cached_tokens: metrics.cached_tokens,
      uncached_input_tokens: uncached_input_tokens(metrics),
      output_tokens: metrics.output_tokens,
      reasoning_tokens: metrics.reasoning_tokens,
      input_cost: format_input_cost(metrics),
      output_cost: format_output_cost(metrics),
      total_cost: format_total_cost(metrics)
    }
  end

  defp empty_usage_totals do
    %{
      input_tokens: nil,
      output_tokens: nil,
      total_tokens: nil,
      cached_tokens: nil,
      reasoning_tokens: nil,
      input_cost: nil,
      output_cost: nil,
      total_cost: nil,
      cost_currency: nil,
      provider_name: nil,
      provider_model: nil,
      provider_response_id: nil
    }
  end

  defp merge_usage_entry(entry, totals) do
    %{
      input_tokens: sum_optional_int(totals.input_tokens, entry.input_tokens),
      output_tokens: sum_optional_int(totals.output_tokens, entry.output_tokens),
      total_tokens: sum_optional_int(totals.total_tokens, entry.total_tokens),
      cached_tokens: sum_optional_int(totals.cached_tokens, entry.cached_tokens),
      reasoning_tokens: sum_optional_int(totals.reasoning_tokens, entry.reasoning_tokens),
      input_cost: add_cost(totals.input_cost, entry.input_cost),
      output_cost: add_cost(totals.output_cost, entry.output_cost),
      total_cost: add_cost(totals.total_cost, entry.total_cost),
      cost_currency: entry.cost_currency || totals.cost_currency,
      provider_name: entry.provider_name || totals.provider_name,
      provider_model: entry.provider_model || totals.provider_model,
      provider_response_id: entry.provider_response_id || totals.provider_response_id
    }
  end

  defp format_cost(%Decimal{} = amount, currency) do
    amount =
      amount
      |> Decimal.round(6)
      |> Decimal.normalize()
      |> Decimal.to_string(:normal)

    case currency do
      nil -> "$#{amount}"
      "USD" -> "$#{amount}"
      currency -> "#{currency} #{amount}"
    end
  end

  defp token_value(nil, _field, fallback), do: fallback
  defp token_value(cost_info, field, _fallback), do: Map.get(cost_info, field)

  defp sum_optional_int(nil, nil), do: nil
  defp sum_optional_int(left, nil), do: left
  defp sum_optional_int(nil, right), do: right
  defp sum_optional_int(left, right), do: left + right

  defp add_cost(nil, nil), do: nil
  defp add_cost(%Decimal{} = left, nil), do: left
  defp add_cost(nil, %Decimal{} = right), do: right
  defp add_cost(%Decimal{} = left, %Decimal{} = right), do: Decimal.add(left, right)

  defp token_total(nil, nil, nil), do: nil

  defp token_total(nil, input_tokens, output_tokens),
    do: (input_tokens || 0) + (output_tokens || 0)

  defp token_total(cost_info, _input_tokens, _output_tokens), do: cost_info.total_tokens

  defp cached_tokens(%CostInfo{cached_tokens: cached_tokens}, _raw, _fallback)
       when is_integer(cached_tokens),
       do: cached_tokens

  defp cached_tokens(
         _cost_info,
         %{"usage" => %{"input_tokens_details" => %{"cached_tokens" => cached_tokens}}},
         _fallback
       )
       when is_integer(cached_tokens),
       do: cached_tokens

  defp cached_tokens(
         _cost_info,
         %{
           "response" => %{
             "usage" => %{"input_tokens_details" => %{"cached_tokens" => cached_tokens}}
           }
         },
         _fallback
       )
       when is_integer(cached_tokens),
       do: cached_tokens

  defp cached_tokens(_cost_info, _raw, cached_tokens) when is_integer(cached_tokens),
    do: cached_tokens

  defp cached_tokens(_cost_info, _raw, _fallback), do: nil

  defp reasoning_tokens(%{reasoning_tokens: reasoning_tokens}) when is_integer(reasoning_tokens),
    do: reasoning_tokens

  defp reasoning_tokens(%{
         raw: %{
           "usage" => %{
             "completion_tokens_details" => %{"reasoning_tokens" => reasoning_tokens}
           }
         }
       })
       when is_integer(reasoning_tokens),
       do: reasoning_tokens

  defp reasoning_tokens(%{
         raw: %{
           "response" => %{
             "usage" => %{
               "output_tokens_details" => %{"reasoning_tokens" => reasoning_tokens}
             }
           }
         }
       })
       when is_integer(reasoning_tokens),
       do: reasoning_tokens

  defp reasoning_tokens(_data), do: nil

  defp cost_value(nil, _field), do: nil
  defp cost_value(cost_info, field), do: Map.get(cost_info, field)

  defp provider_name(nil, provider) when is_atom(provider), do: Atom.to_string(provider)
  defp provider_name(nil, provider), do: provider
  defp provider_name(cost_info, _provider), do: to_string(cost_info.provider_name)

  defp provider_model(nil, %{provider_model: provider_model}) when is_binary(provider_model),
    do: provider_model

  defp provider_model(nil, %{raw: %{"model" => model}}) when is_binary(model), do: model

  defp provider_model(nil, %{raw: %{"response" => %{"model" => model}}}) when is_binary(model),
    do: model

  defp provider_model(nil, _data), do: nil
  defp provider_model(cost_info, _data), do: cost_info.provider_model

  defp provider_response_id(%{response_id: response_id}) when is_binary(response_id),
    do: response_id

  defp provider_response_id(%{raw: %{"id" => response_id}}) when is_binary(response_id),
    do: response_id

  defp provider_response_id(%{raw: %{"response" => %{"id" => response_id}}})
       when is_binary(response_id), do: response_id

  defp provider_response_id(_data), do: nil
end
