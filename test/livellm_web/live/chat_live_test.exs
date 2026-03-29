defmodule LivellmWeb.ChatLiveTest do
  use LivellmWeb.ConnCase

  import Phoenix.LiveViewTest

  alias Decimal
  alias Livellm.Chats
  alias Livellm.ChatsFixtures
  alias Livellm.Config
  alias Livellm.TestSupport.FakeLlmRunner
  alias LlmComposer.Cache.Ets

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
    assert has_element?(view, "#chat-total-tokens.chat-metric-badge--tokens")
    assert has_element?(view, "#chat-total-cost.chat-metric-badge--cost")
    assert has_element?(view, "#chat-reasoning-tokens.chat-metric-badge--reasoning")
    assert has_element?(view, "#chat-cached-tokens.chat-metric-badge--cached")
    assert has_element?(view, "#messages-1-reasoning.chat-reasoning")
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

  test "streaming responses persist normalized chunk metadata from llm_composer", %{conn: conn} do
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

    case Process.whereis(Ets) do
      nil -> start_supervised!({Ets, []})
      _pid -> :ok
    end

    Ets.put(
      "models_dev_api",
      %{
        "openai" => %{
          "models" => %{
            "gpt-5.4-mini" => %{
              "cost" => %{
                "input" => "0.250",
                "output" => "2.000",
                "cache_read" => "0.125"
              }
            }
          }
        }
      },
      60
    )

    _ = :sys.get_state(Process.whereis(Ets))

    Application.put_env(
      :livellm,
      :llm_runner_result,
      {:ok,
       %LlmComposer.LlmResponse{
         provider: :open_ai_responses,
         status: :ok,
         stream: [
           ~s(data: {"type":"response.output_text.delta","delta":"Hello"}),
           ~s(data: {"type":"response.output_text.delta","delta":" world"}),
           ~s(data: {"type":"response.output_item.done","item":{"type":"reasoning","summary":[{"type":"summary_text","text":"Thinking"}]}}),
           ~s(data: {"type":"response.completed","response":{"id":"resp_stream_123","model":"gpt-5.4-mini","usage":{"input_tokens":40,"output_tokens":8,"total_tokens":48,"input_tokens_details":{"cached_tokens":12},"output_tokens_details":{"reasoning_tokens":9}}}})
         ]
       }}
    )

    Application.put_env(:livellm, :llm_runner_test_pid, self())

    Phoenix.PubSub.subscribe(Livellm.PubSub, "chat_stream:#{chat.id}")

    {:ok, view, _html} = live(conn, ~p"/chats/#{chat.id}")

    render_submit(element(view, "#message-form"), %{"message" => "Hello"})

    assert_receive {:fake_llm_runner_called, _provider_config, "gpt-5.4-mini", _history, nil,
                    _chat_id, _opts}

    assert_receive {:stream_done, %Livellm.Chats.Chat{id: chat_id}, assistant_msg}
    assert chat_id == chat.id

    _ = :sys.get_state(view.pid)

    assert render(element(view, "#chat-total-tokens")) =~ "48 tokens"
    assert render(element(view, "#chat-total-cost")) =~ "$0.000025"
    assert render(element(view, "#chat-reasoning-tokens")) =~ "9 reasoning"
    assert render(element(view, "#chat-cached-tokens")) =~ "12 cached"

    assert assistant_msg.content == "Hello world"
    assert assistant_msg.reasoning == "Thinking"
    assert assistant_msg.input_tokens == 40
    assert assistant_msg.output_tokens == 8
    assert assistant_msg.total_tokens == 48
    assert assistant_msg.cached_tokens == 12
    assert assistant_msg.reasoning_tokens == 9
    assert assistant_msg.provider_name == "open_ai_responses"
    assert assistant_msg.provider_model == "gpt-5.4-mini"
    assert assistant_msg.provider_response_id == "resp_stream_123"
    assert Decimal.equal?(assistant_msg.total_cost, Decimal.new("0.000024500000"))
  end

  test "non-streaming tool loops persist reasoning before and after tool execution", %{
    conn: conn
  } do
    provider_config = provider_config_fixture(enabled: true, default_model: "gpt-4.1-mini")

    Application.put_env(
      :livellm,
      :llm_runner_result,
      fn _provider_config, _model, history, _reasoning_effort, _chat_id, _opts ->
        if Enum.any?(history, &match?(%LlmComposer.Message{type: :tool_result}, &1)) do
          FakeLlmRunner.success_response(%{
            provider: :open_ai,
            main_response: %LlmComposer.Message{
              type: :assistant,
              content: "Final answer",
              reasoning: "Second reasoning",
              reasoning_details: [%{"text" => "Second reasoning"}]
            },
            raw: %{"id" => "resp_final"}
          })
        else
          {:ok,
           %LlmComposer.LlmResponse{
             provider: :open_ai,
             status: :ok,
             raw: %{"id" => "resp_tool"},
             main_response: %LlmComposer.Message{
               type: :assistant,
               content: nil,
               reasoning: nil,
               reasoning_details: [%{"text" => "First reasoning"}],
               function_calls: [
                 %LlmComposer.FunctionCall{
                   id: "call_memory_1",
                   name: "memory",
                   arguments: ~s({"action":"list"})
                 }
               ]
             }
           }}
        end
      end
    )

    Application.put_env(:livellm, :llm_runner_test_pid, self())

    {:ok, view, _html} = live(conn, ~p"/")

    render_change(element(view, "#chat-settings-form"), %{
      "provider_id" => Integer.to_string(provider_config.id),
      "model" => "gpt-4.1-mini",
      "reasoning_effort" => "",
      "streaming" => "false"
    })

    render_click(element(view, "#tool-memory"))
    render_submit(element(view, "#message-form"), %{"message" => "Use the memory tool"})

    assert_receive {:fake_llm_runner_called, ^provider_config, "gpt-4.1-mini", first_history, nil,
                    _chat_id, first_opts}

    refute Enum.any?(first_history, &match?(%LlmComposer.Message{type: :tool_result}, &1))
    assert Keyword.get(first_opts, :stream) == false

    assert_receive {:fake_llm_runner_called, ^provider_config, "gpt-4.1-mini", second_history,
                    nil, _chat_id, second_opts}

    assert Enum.any?(second_history, &match?(%LlmComposer.Message{type: :tool_result}, &1))
    assert Keyword.get(second_opts, :stream) == false

    _ = :sys.get_state(view.pid)

    chat = Chats.list_chats() |> List.first()
    assistant_msg = Chats.latest_assistant_message(chat)

    assert assistant_msg.reasoning == "Second reasoning"

    assert assistant_msg.reasoning_details == [
             %{"text" => "First reasoning"},
             %{"text" => "Second reasoning"}
           ]

    assert assistant_msg.reasoning_steps == [
             %{"type" => "reasoning", "content" => "First reasoning"},
             %{"type" => "tool_call", "tool_name" => "memory", "status" => "completed"},
             %{"type" => "reasoning", "content" => "Second reasoning"}
           ]
  end

  test "streaming tool loops persist reasoning before and after tool execution", %{conn: conn} do
    provider_config = provider_config_fixture(enabled: true, default_model: "gpt-4.1-mini")

    Application.put_env(
      :livellm,
      :llm_runner_result,
      fn _provider_config, _model, history, _reasoning_effort, _chat_id, _opts ->
        if Enum.any?(history, &match?(%LlmComposer.Message{type: :tool_result}, &1)) do
          {:ok,
           %LlmComposer.LlmResponse{
             provider: :open_ai,
             status: :ok,
             stream: [
               ~s(data: {"choices":[{"delta":{"reasoning":"Second reasoning","reasoning_details":[{"type":"reasoning.text","text":"Second reasoning"}]},"index":0,"finish_reason":null}]}),
               ~s(data: {"choices":[{"delta":{"content":"Final answer"},"index":0,"finish_reason":null}]}),
               ~s(data: {"choices":[{"delta":{},"index":0,"finish_reason":"stop"}]})
             ]
           }}
        else
          {:ok,
           %LlmComposer.LlmResponse{
             provider: :open_ai,
             status: :ok,
             stream: [
               ~s(data: {"choices":[{"delta":{"reasoning":"First reasoning","reasoning_details":[{"type":"reasoning.text","text":"First reasoning"}]},"index":0,"finish_reason":null}]}),
               ~s(data: {"choices":[{"delta":{"tool_calls":[{"index":0,"id":"call_memory_1","type":"function","function":{"name":"memory","arguments":"{\\"action\\":\\"list\\"}"}}]},"index":0,"finish_reason":null}]}),
               ~s(data: {"choices":[{"delta":{},"index":0,"finish_reason":"tool_calls"}]})
             ]
           }}
        end
      end
    )

    Application.put_env(:livellm, :llm_runner_test_pid, self())

    {:ok, view, _html} = live(conn, ~p"/")

    render_change(element(view, "#chat-settings-form"), %{
      "provider_id" => Integer.to_string(provider_config.id),
      "model" => "gpt-4.1-mini",
      "reasoning_effort" => "",
      "streaming" => "true"
    })

    render_click(element(view, "#tool-memory"))
    render_submit(element(view, "#message-form"), %{"message" => "Use the memory tool"})

    assert_receive {:fake_llm_runner_called, ^provider_config, "gpt-4.1-mini", first_history, nil,
                    _chat_id, first_opts}

    refute Enum.any?(first_history, &match?(%LlmComposer.Message{type: :tool_result}, &1))
    assert Keyword.get(first_opts, :stream) == true

    assert_receive {:fake_llm_runner_called, ^provider_config, "gpt-4.1-mini", second_history,
                    nil, chat_id, second_opts}

    assert Enum.any?(second_history, &match?(%LlmComposer.Message{type: :tool_result}, &1))
    assert Keyword.get(second_opts, :stream) == true

    _ = :sys.get_state(view.pid)

    chat = Chats.get_chat!(chat_id)
    assistant_msg = Chats.latest_assistant_message(chat)

    assert assistant_msg.content == "Final answer"
    assert assistant_msg.reasoning == "Second reasoning"

    assert assistant_msg.reasoning_details == [
             %{"type" => "reasoning.text", "text" => "First reasoning"},
             %{"type" => "reasoning.text", "text" => "Second reasoning"}
           ]

    assert assistant_msg.reasoning_steps == [
             %{"type" => "reasoning", "content" => "First reasoning"},
             %{"type" => "tool_call", "tool_name" => "memory", "status" => "completed"},
             %{"type" => "reasoning", "content" => "Second reasoning"}
           ]
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
