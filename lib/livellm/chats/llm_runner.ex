defmodule Livellm.Chats.LlmRunner do
  @moduledoc """
  Orchestrates LLM calls for chat conversations.

  Handles provider selection, request option building (reasoning effort,
  prompt caching), and dispatches to the appropriate LlmComposer provider.
  """

  @spec run(map() | nil, String.t(), [map()], String.t() | nil, integer(), keyword()) ::
          {:ok, map()} | {:error, term()}

  def run(config, model, history, effort, chat_id, run_opts \\ [])
  def run(nil, _model, _history, _effort, _chat_id, _run_opts), do: {:error, :no_provider}
  def run(_config, "", _history, _effort, _chat_id, _run_opts), do: {:error, :no_model}

  def run(config, model, history, reasoning_effort, chat_id, run_opts) do
    provider_mod = provider_module(config.provider)

    opts =
      [model: model, api_key: config.api_key]
      |> maybe_put_url(config.base_url)
      |> maybe_add_reasoning(config.provider, reasoning_effort)
      |> maybe_add_cache_key(config.provider, chat_id)
      |> maybe_add_previous_response_id(config, model, history)
      |> maybe_put_stream(run_opts[:stream])
      |> maybe_put_functions(run_opts[:functions])

    settings = %LlmComposer.Settings{
      providers: [{provider_mod, opts}],
      system_prompt: "You are a helpful assistant.",
      track_costs: true
    }

    messages = messages_for_completion(history)

    LlmComposer.run_completion(settings, messages)
  end

  @doc false
  def messages_for_completion(history) when is_list(history) do
    Enum.flat_map(history, &to_llm_messages/1)
  end

  @doc false
  def previous_response_id_for_openai_responses(history, model) do
    normalized_model = normalize_openai_responses_model(model)

    history
    |> Enum.reverse()
    |> Enum.find_value(fn
      %{role: "assistant", provider_name: "open_ai_responses"} = message ->
        if normalize_openai_responses_model(message.provider_model) == normalized_model do
          message.provider_response_id
        end

      _message ->
        nil
    end)
  end

  # --- Private ---

  defp maybe_put_url(opts, nil), do: opts
  defp maybe_put_url(opts, url), do: Keyword.put(opts, :url, url)

  defp maybe_put_stream(opts, true), do: Keyword.put(opts, :stream_response, true)
  defp maybe_put_stream(opts, _), do: opts

  defp maybe_put_functions(opts, [_ | _] = functions),
    do: Keyword.put(opts, :functions, functions)

  defp maybe_put_functions(opts, _), do: opts

  defp to_llm_messages(%LlmComposer.Message{} = msg), do: [msg]

  defp to_llm_messages(%{role: "assistant"} = msg) do
    assistant_message = build_message(msg)

    case build_replayed_tool_messages(msg) do
      [] ->
        [assistant_message]

      replayed_tool_messages ->
        [build_tool_call_request_message(msg), replayed_tool_messages, assistant_message]
        |> List.flatten()
    end
  end

  defp to_llm_messages(msg), do: [build_message(msg)]

  defp build_message(msg) do
    %LlmComposer.Message{
      type: message_type(msg.role),
      content: msg.content,
      reasoning: msg.reasoning,
      reasoning_details: msg.reasoning_details
    }
  end

  defp build_tool_call_request_message(msg) do
    %LlmComposer.Message{
      type: :assistant,
      content: nil,
      function_calls: build_function_calls(msg)
    }
  end

  defp build_replayed_tool_messages(msg) do
    msg
    |> build_tool_call_entries()
    |> Enum.map(fn entry ->
      %LlmComposer.Message{
        type: :tool_result,
        content: fetch_tool_call_field(entry, "result"),
        metadata: %{"tool_call_id" => fetch_tool_call_field(entry, "id")}
      }
    end)
  end

  defp build_function_calls(msg) do
    msg
    |> build_tool_call_entries()
    |> Enum.map(fn entry ->
      %LlmComposer.FunctionCall{
        id: fetch_tool_call_field(entry, "id"),
        name: fetch_tool_call_field(entry, "name"),
        arguments: fetch_tool_call_field(entry, "arguments"),
        type: "function"
      }
    end)
  end

  defp build_tool_call_entries(msg) do
    msg
    |> tool_calls()
    |> List.wrap()
    |> Enum.with_index(1)
    |> Enum.map(fn {entry, index} ->
      entry
      |> ensure_tool_call_id(msg, index)
      |> ensure_tool_call_arguments()
    end)
    |> Enum.filter(&replayable_tool_call?/1)
  end

  defp replayable_tool_call?(entry) do
    is_binary(fetch_tool_call_field(entry, "id")) and
      is_binary(fetch_tool_call_field(entry, "name")) and
      is_binary(fetch_tool_call_field(entry, "result"))
  end

  defp ensure_tool_call_id(entry, msg, index) do
    case fetch_tool_call_field(entry, "id") do
      id when is_binary(id) and id != "" ->
        entry

      _ ->
        put_tool_call_field(entry, "id", "persisted_tool_call_#{msg.id || "message"}_#{index}")
    end
  end

  defp ensure_tool_call_arguments(entry) do
    case fetch_tool_call_field(entry, "arguments") do
      arguments when is_binary(arguments) and arguments != "" ->
        entry

      _ ->
        put_tool_call_field(entry, "arguments", "{}")
    end
  end

  defp tool_calls(%{tool_calls: tool_calls}), do: tool_calls
  defp tool_calls(_msg), do: nil

  defp fetch_tool_call_field(entry, "id") when is_map(entry),
    do: Map.get(entry, "id") || Map.get(entry, :id)

  defp fetch_tool_call_field(entry, "name") when is_map(entry),
    do: Map.get(entry, "name") || Map.get(entry, :name)

  defp fetch_tool_call_field(entry, "arguments") when is_map(entry),
    do: Map.get(entry, "arguments") || Map.get(entry, :arguments)

  defp fetch_tool_call_field(entry, "result") when is_map(entry),
    do: Map.get(entry, "result") || Map.get(entry, :result)

  defp put_tool_call_field(entry, "id", value) when is_map(entry) do
    if Map.has_key?(entry, "id"),
      do: Map.put(entry, "id", value),
      else: Map.put(entry, :id, value)
  end

  defp put_tool_call_field(entry, "arguments", value) when is_map(entry) do
    if Map.has_key?(entry, "arguments"),
      do: Map.put(entry, "arguments", value),
      else: Map.put(entry, :arguments, value)
  end

  defp provider_module("openai"), do: LlmComposer.Providers.OpenAI
  defp provider_module("openai_responses"), do: LlmComposer.Providers.OpenAIResponses
  defp provider_module("openrouter"), do: LlmComposer.Providers.OpenRouter
  defp provider_module("ollama"), do: LlmComposer.Providers.Ollama
  defp provider_module("google"), do: LlmComposer.Providers.Google

  defp maybe_add_reasoning(opts, "openrouter", effort) when effort not in [nil, ""] do
    Keyword.put(opts, :request_params, %{"reasoning" => %{"enabled" => true, "effort" => effort}})
  end

  defp maybe_add_reasoning(opts, "openai_responses", effort) when effort not in [nil, ""] do
    Keyword.put(opts, :reasoning_effort, effort)
  end

  defp maybe_add_reasoning(opts, _provider, _effort), do: opts

  defp maybe_add_cache_key(opts, "openai_responses", chat_id) do
    Keyword.update(opts, :request_params, %{"prompt_cache_key" => "chat_#{chat_id}"}, fn params ->
      Map.put(params, "prompt_cache_key", "chat_#{chat_id}")
    end)
  end

  defp maybe_add_cache_key(opts, "openrouter", _chat_id) do
    model = Keyword.get(opts, :model, "")

    if String.starts_with?(model, "anthropic/") do
      Keyword.update(
        opts,
        :request_params,
        %{"cache_control" => %{"type" => "ephemeral"}},
        fn params -> Map.put(params, "cache_control", %{"type" => "ephemeral"}) end
      )
    else
      opts
    end
  end

  defp maybe_add_cache_key(opts, _provider, _chat_id), do: opts

  defp maybe_add_previous_response_id(opts, %{provider: "openai_responses"}, model, history) do
    previous_response_id = previous_response_id_for_openai_responses(history, model)

    if is_binary(previous_response_id) and previous_response_id != "" do
      Keyword.put(opts, :previous_response_id, previous_response_id)
    else
      opts
    end
  end

  defp maybe_add_previous_response_id(opts, _config, _model, _history), do: opts

  defp normalize_openai_responses_model(model) when is_binary(model) do
    Regex.replace(~r/-\d{4}-\d{2}-\d{2}$/, model, "")
  end

  defp normalize_openai_responses_model(_model), do: nil

  defp message_type("user"), do: :user
  defp message_type("assistant"), do: :assistant
  defp message_type("system"), do: :system
  defp message_type("tool"), do: :tool_result
  defp message_type(role) when is_binary(role), do: role
end
