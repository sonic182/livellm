defmodule Livellm.TestSupport.FakeLlmRunner do
  @moduledoc """
  Test double for `Livellm.Chats.LlmRunner`.
  """

  alias LlmComposer.LlmResponse

  def run(provider_config, model, history, reasoning_effort, chat_id, _opts \\ []) do
    notify_test_process(provider_config, model, history, reasoning_effort, chat_id)

    case Application.fetch_env(:livellm, :llm_runner_result) do
      {:ok, result} when is_function(result, 5) ->
        result.(provider_config, model, history, reasoning_effort, chat_id)

      {:ok, result} ->
        result

      :error ->
        {:error, :missing_fake_llm_runner_result}
    end
  end

  def success_response(attrs \\ %{}) do
    main_response =
      Map.get_lazy(attrs, :main_response, fn ->
        %LlmComposer.Message{type: :assistant, content: "Stubbed assistant reply"}
      end)

    response =
      %LlmResponse{
        provider: Map.get(attrs, :provider, :open_ai),
        status: :ok,
        main_response: main_response,
        input_tokens: Map.get(attrs, :input_tokens),
        output_tokens: Map.get(attrs, :output_tokens),
        cost_info: Map.get(attrs, :cost_info),
        raw: Map.get(attrs, :raw, %{"id" => "fake-response"})
      }

    {:ok, response}
  end

  defp notify_test_process(provider_config, model, history, reasoning_effort, chat_id) do
    case Application.get_env(:livellm, :llm_runner_test_pid) do
      pid when is_pid(pid) ->
        send(
          pid,
          {:fake_llm_runner_called, provider_config, model, history, reasoning_effort, chat_id}
        )

      _ ->
        :ok
    end
  end
end
