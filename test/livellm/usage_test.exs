defmodule Livellm.UsageTest do
  use ExUnit.Case, async: true

  alias Decimal
  alias Livellm.Usage
  alias LlmComposer.Cache.Ets

  test "aggregate_chat_metrics sums assistant tokens and costs" do
    messages = [
      %{role: "user", total_tokens: 999},
      %{
        role: "assistant",
        input_tokens: 10,
        output_tokens: 5,
        total_tokens: 15,
        reasoning_tokens: 4,
        total_cost: Decimal.new("0.001000"),
        cost_currency: "USD"
      },
      %{
        role: "assistant",
        input_tokens: 20,
        output_tokens: 8,
        total_tokens: 28,
        reasoning_tokens: 7,
        total_cost: Decimal.new("0.002500"),
        cost_currency: "USD"
      }
    ]

    metrics = Usage.aggregate_chat_metrics(messages)

    assert metrics.input_tokens == 30
    assert metrics.output_tokens == 13
    assert metrics.total_tokens == 43
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
      reasoning_tokens: 12,
      total_cost: Decimal.new("0.000056"),
      currency: "USD",
      cost_tracked?: true
    }

    assert Usage.format_total_tokens(priced_metrics) == "48 tokens"
    assert Usage.format_reasoning_tokens(priced_metrics) == "12 reasoning"
    assert Usage.format_total_cost(priced_metrics) == "$0.000056"
  end

  test "stream_cost_tracking_attrs derives openrouter pricing from final usage chunk" do
    case Process.whereis(Ets) do
      nil -> start_supervised!({Ets, []})
      _pid -> :ok
    end

    Ets.put(
      "minimax/minimax-m2.7-20260318",
      %{
        "data" => %{
          "endpoints" => [
            %{
              "provider_name" => "Minimax",
              "pricing" => %{
                "prompt" => "0.0000003",
                "completion" => "0.0000012"
              }
            }
          ]
        }
      },
      60
    )

    _ = :sys.get_state(Process.whereis(Ets))

    attrs =
      Usage.stream_cost_tracking_attrs(
        :open_router,
        %{input_tokens: 30, output_tokens: 472, total_tokens: 502},
        %{
          "model" => "minimax/minimax-m2.7-20260318",
          "provider" => "Minimax",
          "usage" => %{
            "cost" => 5.754e-4,
            "completion_tokens_details" => %{"reasoning_tokens" => 128}
          }
        }
      )

    assert attrs.input_tokens == 30
    assert attrs.output_tokens == 472
    assert attrs.total_tokens == 502
    assert attrs.reasoning_tokens == 128
    assert attrs.provider_name == "Minimax"
    assert attrs.provider_model == "minimax/minimax-m2.7-20260318"
    assert attrs.cost_currency == "USD"
    assert Decimal.equal?(attrs.input_cost, Decimal.new("0.000009000000"))
    assert Decimal.equal?(attrs.output_cost, Decimal.new("0.0005664000000"))
    assert Decimal.equal?(attrs.total_cost, Decimal.new("0.0005754000000"))
  end
end
