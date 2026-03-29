defmodule Livellm.Chats.LlmRunnerTest do
  use ExUnit.Case, async: true

  alias Livellm.Chats.LlmRunner

  test "previous_response_id_for_openai_responses/2 reuses response ids across alias and snapshot models" do
    history = [
      %{
        role: "assistant",
        provider_name: "open_ai_responses",
        provider_model: "gpt-5.4-mini-2026-03-17",
        provider_response_id: "resp_prev_123"
      }
    ]

    assert LlmRunner.previous_response_id_for_openai_responses(history, "gpt-5.4-mini") ==
             "resp_prev_123"

    assert LlmRunner.previous_response_id_for_openai_responses(
             history,
             "gpt-5.4-mini-2026-03-17"
           ) == "resp_prev_123"
  end

  test "previous_response_id_for_openai_responses/2 skips unrelated assistant messages" do
    history = [
      %{
        role: "assistant",
        provider_name: "open_ai_responses",
        provider_model: "gpt-5.4",
        provider_response_id: "resp_wrong_model"
      },
      %{
        role: "assistant",
        provider_name: "open_ai",
        provider_model: "gpt-5.4-mini",
        provider_response_id: "resp_wrong_provider"
      }
    ]

    assert LlmRunner.previous_response_id_for_openai_responses(history, "gpt-5.4-mini") == nil
  end

  test "run/6 maps persisted chat roles without relying on existing atoms" do
    config = %{provider: "openai", api_key: "test-key", base_url: nil}

    history = [
      %{role: "system", content: "System", reasoning: nil, reasoning_details: nil},
      %{role: "user", content: "User", reasoning: nil, reasoning_details: nil},
      %{role: "assistant", content: "Assistant", reasoning: "thinking", reasoning_details: []},
      %{role: "tool", content: "Tool output", reasoning: nil, reasoning_details: nil}
    ]

    assert {:error, _reason} = LlmRunner.run(config, "gpt-4.1-mini", history, nil, 1)
  end

  test "messages_for_completion/1 expands persisted tool turns into assistant, tool_result, and final assistant messages" do
    history = [
      %{role: "user", content: "Remember this", reasoning: nil, reasoning_details: nil},
      %{
        id: 12,
        role: "assistant",
        content: "Saved it for later.",
        reasoning: "Final reasoning",
        reasoning_details: [%{"text" => "First reasoning"}, %{"text" => "Final reasoning"}],
        tool_calls: [
          %{
            "id" => "call_memory_1",
            "name" => "memory",
            "arguments" => ~s({"action":"write","title":"Note","data":"Remember this"}),
            "result" => "Saved memory ID 42."
          }
        ]
      }
    ]

    assert [
             %LlmComposer.Message{type: :user, content: "Remember this"},
             %LlmComposer.Message{
               type: :assistant,
               content: nil,
               function_calls: [
                 %LlmComposer.FunctionCall{
                   id: "call_memory_1",
                   name: "memory",
                   arguments: ~s({"action":"write","title":"Note","data":"Remember this"})
                 }
               ]
             },
             %LlmComposer.Message{
               type: :tool_result,
               content: "Saved memory ID 42.",
               metadata: %{"tool_call_id" => "call_memory_1"}
             },
             %LlmComposer.Message{
               type: :assistant,
               content: "Saved it for later.",
               reasoning: "Final reasoning",
               reasoning_details: [%{"text" => "First reasoning"}, %{"text" => "Final reasoning"}]
             }
           ] = LlmRunner.messages_for_completion(history)
  end

  test "messages_for_completion/1 synthesizes stable tool call ids for legacy persisted entries" do
    history = [
      %{
        id: 99,
        role: "assistant",
        content: "Done",
        reasoning: nil,
        reasoning_details: nil,
        tool_calls: [
          %{"name" => "memory", "arguments" => ~s({"action":"list"}), "result" => "No memories."}
        ]
      }
    ]

    assert [
             %LlmComposer.Message{
               type: :assistant,
               function_calls: [
                 %LlmComposer.FunctionCall{id: "persisted_tool_call_99_1", name: "memory"}
               ]
             },
             %LlmComposer.Message{
               type: :tool_result,
               metadata: %{"tool_call_id" => "persisted_tool_call_99_1"}
             },
             %LlmComposer.Message{type: :assistant, content: "Done"}
           ] = LlmRunner.messages_for_completion(history)
  end
end
