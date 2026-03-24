defmodule Livellm.UsageTest do
  use ExUnit.Case, async: true

  alias Decimal
  alias Livellm.Usage
  alias LlmComposer.CostInfo
  alias LlmComposer.StreamChunk

  test "aggregate_chat_metrics sums assistant tokens and costs" do
    messages = [
      %{role: "user", total_tokens: 999},
      %{
        role: "assistant",
        input_tokens: 10,
        output_tokens: 5,
        total_tokens: 15,
        cached_tokens: 3,
        reasoning_tokens: 4,
        total_cost: Decimal.new("0.001000"),
        cost_currency: "USD"
      },
      %{
        role: "assistant",
        input_tokens: 20,
        output_tokens: 8,
        total_tokens: 28,
        cached_tokens: 2,
        reasoning_tokens: 7,
        total_cost: Decimal.new("0.002500"),
        cost_currency: "USD"
      }
    ]

    metrics = Usage.aggregate_chat_metrics(messages)

    assert metrics.input_tokens == 30
    assert metrics.output_tokens == 13
    assert metrics.total_tokens == 43
    assert metrics.cached_tokens == 5
    assert metrics.reasoning_tokens == 11
    assert Decimal.equal?(metrics.total_cost, Decimal.new("0.003500"))
    assert metrics.currency == "USD"
    assert metrics.cost_tracked?
  end

  test "formatters hide empty metrics and render priced metrics" do
    empty_metrics = Usage.empty_chat_metrics()

    assert Usage.format_total_tokens(empty_metrics) == nil
    assert Usage.format_total_cost(empty_metrics) == nil

    priced_metrics = %{
      total_tokens: 48,
      cached_tokens: 9,
      reasoning_tokens: 12,
      total_cost: Decimal.new("0.000056"),
      currency: "USD",
      cost_tracked?: true
    }

    assert Usage.format_total_tokens(priced_metrics) == "48 tokens"
    assert Usage.format_cached_tokens(priced_metrics) == "9 cached"
    assert Usage.format_reasoning_tokens(priced_metrics) == "12 reasoning"
    assert Usage.format_total_cost(priced_metrics) == "$0.000056"
  end

  test "stream_chunk_attrs uses normalized chunk usage and cost info" do
    chunk = %StreamChunk{
      provider: :open_router,
      type: :usage,
      usage: %{
        input_tokens: 30,
        output_tokens: 472,
        total_tokens: 502,
        cached_tokens: nil,
        reasoning_tokens: 128
      },
      cost_info:
        CostInfo.new(
          :open_router,
          "minimax/minimax-m2.7-20260318",
          30,
          472,
          provider_name: "Minimax",
          input_price_per_million: Decimal.new("0.300000"),
          output_price_per_million: Decimal.new("1.200000"),
          currency: "USD"
        ),
      raw: %{"id" => "chunk_123"}
    }

    attrs = Usage.stream_chunk_attrs(chunk)

    assert attrs.input_tokens == 30
    assert attrs.output_tokens == 472
    assert attrs.total_tokens == 502
    assert attrs.reasoning_tokens == 128
    assert attrs.provider_name == "Minimax"
    assert attrs.provider_model == "minimax/minimax-m2.7-20260318"
    assert attrs.provider_response_id == "chunk_123"
    assert attrs.cost_currency == "USD"
    assert Decimal.equal?(attrs.input_cost, Decimal.new("0.000009000000"))
    assert Decimal.equal?(attrs.output_cost, Decimal.new("0.0005664000000"))
    assert Decimal.equal?(attrs.total_cost, Decimal.new("0.0005754000000"))
  end

  test "stream_chunk_attrs returns nil costs when the chunk has no cost_info" do
    chunk = %StreamChunk{
      provider: :open_ai_responses,
      type: :done,
      usage: %{
        input_tokens: 40,
        output_tokens: 54,
        total_tokens: 94,
        cached_tokens: 11,
        reasoning_tokens: 43
      },
      raw: %{
        "response" => %{
          "id" => "resp_123",
          "model" => "gpt-5.4-mini"
        }
      }
    }

    attrs = Usage.stream_chunk_attrs(chunk)

    assert attrs.input_tokens == 40
    assert attrs.output_tokens == 54
    assert attrs.total_tokens == 94
    assert attrs.cached_tokens == 11
    assert attrs.reasoning_tokens == 43
    assert attrs.provider_name == "open_ai_responses"
    assert attrs.provider_model == "gpt-5.4-mini"
    assert attrs.provider_response_id == "resp_123"
    assert attrs.cost_currency == nil
    assert attrs.input_cost == nil
    assert attrs.output_cost == nil
    assert attrs.total_cost == nil
  end

  test "cost_tracking_attrs prefers normalized llm_response fields" do
    llm_response = %LlmComposer.LlmResponse{
      provider: :open_ai_responses,
      provider_model: "gpt-5.4-mini-2026-03-17",
      response_id: "resp_999",
      input_tokens: 100,
      output_tokens: 25,
      cached_tokens: 40,
      reasoning_tokens: 8,
      raw: %{
        "response" => %{
          "id" => "resp_999",
          "usage" => %{"output_tokens_details" => %{"reasoning_tokens" => 99}}
        }
      }
    }

    attrs = Usage.cost_tracking_attrs(llm_response)

    assert attrs.cached_tokens == 40
    assert attrs.reasoning_tokens == 8
    assert attrs.provider_model == "gpt-5.4-mini-2026-03-17"
    assert attrs.provider_response_id == "resp_999"
  end
end
