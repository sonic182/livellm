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
        reasoning: "Thinking through the answer",
        input_tokens: 12,
        output_tokens: 6,
        total_tokens: 18,
        cached_tokens: 4,
        reasoning_tokens: 5,
        total_cost: Decimal.new("0.003000"),
        cost_currency: "USD",
        provider_name: "open_ai",
        provider_model: "gpt-4.1-mini"
      })

    {:ok, view, _html} = live(conn, ~p"/chats/#{chat.id}")

    assert has_element?(view, "#chat-metrics")
    assert render(element(view, "#chat-total-tokens")) =~ "18 tokens"
    popover = render(element(view, "#chat-tokens-popover"))
    assert popover =~ "Token Breakdown"
    assert popover =~ "Input"
    assert popover =~ "12"
    assert popover =~ "Cached input"
    assert popover =~ "4"
    assert popover =~ "Uncached input"
    assert popover =~ "8"
    assert popover =~ "Output"
    assert popover =~ "6"
    assert popover =~ "Reasoning"
    assert popover =~ "5"
    assert popover =~ "Input cost"
    assert popover =~ "Output cost"
    assert popover =~ "Total cost"
    assert render(element(view, "#chat-total-cost")) =~ "$0.003"
    assert render(element(view, "#chat-reasoning-tokens")) =~ "5 reasoning"
    assert render(element(view, "#chat-cached-tokens")) =~ "4 cached"
    assert has_element?(view, "#messages-1-reasoning")
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

  test "assistant messages render markdown and sanitize raw html", %{conn: conn} do
    chat = ChatsFixtures.chat_fixture()

    {:ok, _message} =
      Chats.create_message(chat, %{
        role: "assistant",
        content: """
        # Release Notes

        Visit [OpenAI](https://example.com)

        - first
        - second

        ```elixir
        IO.puts("hello")
        ```

        <script>alert("boom")</script>
        """
      })

    {:ok, view, _html} = live(conn, ~p"/chats/#{chat.id}")

    assert has_element?(view, "#messages-1 .chat-markdown h1")
    assert has_element?(view, "#messages-1 .chat-markdown a[href=\"https://example.com\"]")
    assert has_element?(view, "#messages-1 .chat-markdown ul li")
    assert has_element?(view, "#messages-1 .chat-markdown pre code")
    refute has_element?(view, "#messages-1 script")
  end

  test "sending a message updates the aggregate after the assistant response", %{conn: conn} do
    provider_config_fixture(enabled: true, default_model: "gpt-4.1-mini")

    Application.put_env(
      :livellm,
      :llm_runner_result,
      FakeLlmRunner.success_response(%{
        main_response: %LlmComposer.Message{
          type: :assistant,
          content: "Stubbed assistant reply",
          reasoning: "Thinking through the answer"
        },
        input_tokens: 40,
        output_tokens: 8,
        cached_tokens: 12,
        cost_info:
          LlmComposer.CostInfo.new(
            :open_ai,
            "gpt-4.1-mini",
            40,
            8,
            cached_tokens: 12,
            input_price_per_million: Decimal.new("1.0"),
            cache_read_price_per_million: Decimal.new("0.25"),
            output_price_per_million: Decimal.new("2.0"),
            currency: "USD"
          ),
        raw: %{
          "model" => "gpt-4.1-mini",
          "usage" => %{"completion_tokens_details" => %{"reasoning_tokens" => 9}}
        }
      })
    )

    Application.put_env(:livellm, :llm_runner_test_pid, self())

    {:ok, view, _html} = live(conn, ~p"/")

    render_submit(element(view, "#message-form"), %{"message" => "Hello"})

    assert_receive {:fake_llm_runner_called, _provider_config, "gpt-4.1-mini", _history, nil,
                    _chat_id, _opts}

    _ = :sys.get_state(view.pid)

    assert has_element?(view, "#chat-total-tokens")
    assert render(element(view, "#chat-total-tokens")) =~ "48 tokens"
    popover = render(element(view, "#chat-tokens-popover"))
    assert popover =~ "Cached input"
    assert popover =~ "12"
    assert popover =~ "Uncached input"
    assert popover =~ "28"
    assert render(element(view, "#chat-total-cost")) =~ "$0.000047"
    assert render(element(view, "#chat-reasoning-tokens")) =~ "9 reasoning"
    assert render(element(view, "#chat-cached-tokens")) =~ "12 cached"
    assert has_element?(view, "#messages-2-reasoning")
  end

  test "sending a follow-up openai responses message reuses previous_response_id across alias and snapshot models",
       %{conn: conn} do
    provider_config =
      provider_config_fixture(
        provider: "openai_responses",
        enabled: true,
        default_model: "gpt-5.4-mini"
      )

    chat =
      ChatsFixtures.chat_fixture(%{
        model: "gpt-5.4-mini",
        provider_config_id: provider_config.id
      })

    {:ok, _assistant_msg} =
      Chats.create_message(chat, %{
        role: "assistant",
        content: "First reply",
        provider_name: "open_ai_responses",
        provider_model: "gpt-5.4-mini-2026-03-17",
        provider_response_id: "resp_prev_123"
      })

    Application.put_env(
      :livellm,
      :llm_runner_result,
      FakeLlmRunner.success_response(%{
        provider: :open_ai_responses,
        main_response: %LlmComposer.Message{
          type: :assistant,
          content: "Follow-up reply"
        },
        raw: %{"id" => "resp_next_456", "model" => "gpt-5.4-mini-2026-03-17"}
      })
    )

    Application.put_env(:livellm, :llm_runner_test_pid, self())

    {:ok, view, _html} = live(conn, ~p"/chats/#{chat.id}")
    chat_id = chat.id

    render_submit(element(view, "#message-form"), %{"message" => "Second turn"})

    assert_receive {:fake_llm_runner_called, provider_config_called, "gpt-5.4-mini", _history,
                    nil, ^chat_id, opts}

    assert provider_config_called.id == provider_config.id
    assert Keyword.get(opts, :stream) == true
  end

  test "streaming content renders partial markdown and finalizes into a persisted assistant message",
       %{conn: conn} do
    chat = ChatsFixtures.chat_fixture()

    {:ok, view, _html} = live(conn, ~p"/")

    send(view.pid, {:stream_chunk, chat, "# Partial title\n\n`still typing"})
    _ = :sys.get_state(view.pid)

    assert has_element?(view, "#streaming-message .chat-markdown h1")
    assert has_element?(view, "#streaming-message .chat-markdown code")

    {:ok, assistant_msg} =
      Livellm.Chats.create_message(chat, %{
        role: "assistant",
        content: """
        ## Final answer

        ```elixir
        IO.puts("done")
        ```
        """
      })

    send(view.pid, {:stream_done, chat, assistant_msg})

    _ = :sys.get_state(view.pid)

    refute has_element?(view, "#streaming-message")
    assert has_element?(view, "#messages-1 .chat-markdown h2")
    assert has_element?(view, "#messages-1 .chat-markdown pre code")
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
