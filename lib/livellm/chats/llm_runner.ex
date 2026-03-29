defmodule Livellm.Chats.LlmRunner do
  @moduledoc """
  Orchestrates LLM calls for chat conversations.

  Handles provider selection, request option building (reasoning effort,
  prompt caching), and dispatches to the appropriate LlmComposer provider.
  """

  alias LlmComposer.FunctionCallExtractors

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

    messages = Enum.map(history, &to_llm_message/1)

    LlmComposer.run_completion(settings, messages)
  end

  @doc """
  Consumes a raw provider stream and returns fully accumulated data including
  any tool calls reconstructed from delta fragments.

  This is a pure data function — no broadcasting or side effects. Useful for
  scripts, tests, and background jobs. `chat_live.ex` uses a parallel reduce
  loop that also broadcasts chunks in real-time.

  Returns a map with:
    - `:content` — accumulated text
    - `:reasoning` — accumulated reasoning text
    - `:reasoning_details` — accumulated reasoning detail fragments
    - `:final_chunk` — last `:done` or `:usage` chunk (carries token counts)
    - `:tool_calls` — list of `LlmComposer.FunctionCall` structs, or `nil`
  """
  @spec collect_stream(Enumerable.t(), atom(), String.t()) :: %{
          content: String.t(),
          reasoning: String.t(),
          reasoning_details: list(),
          final_chunk: LlmComposer.StreamChunk.t() | nil,
          tool_calls: [LlmComposer.FunctionCall.t()] | nil
        }
  def collect_stream(stream, provider, model) do
    initial = %{
      content: "",
      reasoning: "",
      reasoning_details: [],
      final_chunk: nil,
      tool_calls_acc: %{}
    }

    final =
      stream
      |> LlmComposer.parse_stream_response(provider, track_costs: true, model: model)
      |> Enum.reduce(initial, &accumulate_chunk/2)

    tool_calls = build_tool_calls_from_acc(final.tool_calls_acc)

    final
    |> Map.delete(:tool_calls_acc)
    |> Map.put(:tool_calls, tool_calls)
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

  defp to_llm_message(%LlmComposer.Message{} = msg), do: msg

  defp to_llm_message(msg) do
    %LlmComposer.Message{
      type: message_type(msg.role),
      content: msg.content,
      reasoning: msg.reasoning,
      reasoning_details: msg.reasoning_details
    }
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

  # --- collect_stream helpers ---

  defp accumulate_chunk(%{type: :text_delta, text: text} = _chunk, acc) when is_binary(text) do
    %{acc | content: acc.content <> text}
  end

  defp accumulate_chunk(%{type: :reasoning_delta} = chunk, acc) do
    reasoning = chunk.reasoning || ""
    details = chunk.reasoning_details || []

    %{
      acc
      | reasoning: acc.reasoning <> reasoning,
        reasoning_details: acc.reasoning_details ++ details
    }
  end

  defp accumulate_chunk(%{type: :tool_call_delta, tool_call: deltas} = _chunk, acc)
       when is_list(deltas) do
    %{acc | tool_calls_acc: merge_tool_call_deltas(acc.tool_calls_acc, deltas)}
  end

  defp accumulate_chunk(%{type: :usage} = chunk, acc) do
    %{acc | final_chunk: chunk}
  end

  defp accumulate_chunk(%{type: :done} = chunk, acc) do
    final_chunk =
      if not is_nil(chunk.usage) or not is_nil(chunk.cost_info) or is_nil(acc.final_chunk) do
        chunk
      else
        acc.final_chunk
      end

    %{acc | final_chunk: final_chunk}
  end

  defp accumulate_chunk(_chunk, acc), do: acc

  defp merge_tool_call_deltas(tool_calls_acc, deltas) do
    Enum.reduce(deltas, tool_calls_acc, fn delta, acc ->
      idx = delta["index"]

      if is_nil(idx) do
        acc
      else
        existing = Map.get(acc, idx, %{})
        args_so_far = get_in(existing, ["function", "arguments"]) || ""
        new_args = args_so_far <> (get_in(delta, ["function", "arguments"]) || "")

        # Deep-merge the "function" sub-map so the "name" from the first chunk
        # is not overwritten by later chunks that only carry "arguments".
        merged_function =
          Map.merge(
            Map.get(existing, "function", %{}),
            Map.get(delta, "function", %{})
          )
          |> Map.put("arguments", new_args)

        updated =
          existing
          |> Map.merge(delta)
          |> Map.put("function", merged_function)

        Map.put(acc, idx, updated)
      end
    end)
  end

  defp build_tool_calls_from_acc(tool_calls_acc) when map_size(tool_calls_acc) == 0, do: nil

  defp build_tool_calls_from_acc(tool_calls_acc) do
    sorted =
      tool_calls_acc
      |> Map.values()
      |> Enum.sort_by(& &1["index"])

    FunctionCallExtractors.from_tool_calls(%{"tool_calls" => sorted})
  end
end
