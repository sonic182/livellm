defmodule LivellmWeb.ChatLiveTest do
  use LivellmWeb.ConnCase

  import Phoenix.LiveViewTest

  alias Decimal
  alias Livellm.Chats
  alias Livellm.ChatsFixtures
  alias Livellm.Config
  alias Livellm.TestSupport.FakeLlmRunner

  setup do
    original_runner = Application.get_env(:livellm, :llm_runner)
    original_result = Application.get_env(:livellm, :llm_runner_result)
    original_test_pid = Application.get_env(:livellm, :llm_runner_test_pid)

    Application.put_env(:livellm, :llm_runner, FakeLlmRunner)

    on_exit(fn ->
      restore_env(:llm_runner, original_runner)
      restore_env(:llm_runner_result, original_result)
      restore_env(:llm_runner_test_pid, original_test_pid)
    end)

    :ok
  end

  test "existing chats show aggregated tokens and cost in the header", %{conn: conn} do
    chat = ChatsFixtures.chat_fixture()

    {:ok, _message} =
      Chats.create_message(chat, %{
        role: "assistant",
        content: "Tracked reply",
        input_tokens: 12,
        output_tokens: 6,
        total_tokens: 18,
        total_cost: Decimal.new("0.003000"),
        cost_currency: "USD",
        provider_name: "open_ai",
        provider_model: "gpt-4.1-mini"
      })

    {:ok, view, _html} = live(conn, ~p"/chats/#{chat.id}")

    assert has_element?(view, "#chat-metrics")
    assert render(element(view, "#chat-total-tokens")) =~ "18 tokens"
    assert render(element(view, "#chat-total-cost")) =~ "$0.003"
  end

  test "existing chats show tokens without cost when pricing is unavailable", %{conn: conn} do
    chat = ChatsFixtures.chat_fixture()

    {:ok, _message} =
      Chats.create_message(chat, %{
        role: "assistant",
        content: "Tracked reply",
        input_tokens: 20,
        output_tokens: 10,
        total_tokens: 30,
        provider_name: "open_ai",
        provider_model: "gpt-4.1-mini"
      })

    {:ok, view, _html} = live(conn, ~p"/chats/#{chat.id}")

    assert has_element?(view, "#chat-total-tokens")
    refute has_element?(view, "#chat-total-cost")
  end

  test "new chats start without aggregate metrics", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")

    refute has_element?(view, "#chat-metrics")
  end

  test "sending a message updates the aggregate after the assistant response", %{conn: conn} do
    provider_config_fixture(enabled: true, default_model: "gpt-4.1-mini")

    Application.put_env(
      :livellm,
      :llm_runner_result,
      FakeLlmRunner.success_response(%{
        input_tokens: 40,
        output_tokens: 8,
        cost_info:
          LlmComposer.CostInfo.new(
            :open_ai,
            "gpt-4.1-mini",
            40,
            8,
            input_price_per_million: Decimal.new("1.0"),
            output_price_per_million: Decimal.new("2.0"),
            currency: "USD"
          ),
        raw: %{"model" => "gpt-4.1-mini"}
      })
    )

    Application.put_env(:livellm, :llm_runner_test_pid, self())

    {:ok, view, _html} = live(conn, ~p"/")

    render_submit(element(view, "#message-form"), %{"message" => "Hello"})

    assert_receive {:fake_llm_runner_called, _provider_config, "gpt-4.1-mini", _history, nil,
                    _chat_id}

    _ = :sys.get_state(view.pid)

    assert has_element?(view, "#chat-total-tokens")
    assert render(element(view, "#chat-total-tokens")) =~ "48 tokens"
    assert render(element(view, "#chat-total-cost")) =~ "$0.000056"
  end

  defp provider_config_fixture(attrs) do
    {:ok, config} =
      attrs
      |> Enum.into(%{
        provider: "openai",
        label: "Primary",
        api_key: "test-key",
        default_model: "gpt-4.1-mini",
        enabled: false
      })
      |> Config.create_provider_config()

    config
  end

  defp restore_env(key, nil), do: Application.delete_env(:livellm, key)
  defp restore_env(key, value), do: Application.put_env(:livellm, key, value)
end
