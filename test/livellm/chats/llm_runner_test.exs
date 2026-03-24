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
end
