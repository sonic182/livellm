defmodule Livellm.UsageTest do
  use ExUnit.Case, async: true

  alias Decimal
  alias Livellm.Usage

  test "aggregate_chat_metrics sums assistant tokens and costs" do
    messages = [
      %{role: "user", total_tokens: 999},
      %{
        role: "assistant",
        input_tokens: 10,
        output_tokens: 5,
        total_tokens: 15,
        total_cost: Decimal.new("0.001000"),
        cost_currency: "USD"
      },
      %{
        role: "assistant",
        input_tokens: 20,
        output_tokens: 8,
        total_tokens: 28,
        total_cost: Decimal.new("0.002500"),
        cost_currency: "USD"
      }
    ]

    metrics = Usage.aggregate_chat_metrics(messages)

    assert metrics.input_tokens == 30
    assert metrics.output_tokens == 13
    assert metrics.total_tokens == 43
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
      total_cost: Decimal.new("0.000056"),
      currency: "USD",
      cost_tracked?: true
    }

    assert Usage.format_total_tokens(priced_metrics) == "48 tokens"
    assert Usage.format_total_cost(priced_metrics) == "$0.000056"
  end
end
