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
    opts = [model: model, api_key: config.api_key]
    opts = if config.base_url, do: Keyword.put(opts, :url, config.base_url), else: opts
    opts = maybe_add_reasoning(opts, config.provider, reasoning_effort)
    opts = maybe_add_cache_key(opts, config.provider, chat_id)
    opts = if run_opts[:stream], do: Keyword.put(opts, :stream_response, true), else: opts

    settings = %LlmComposer.Settings{
      providers: [{provider_mod, opts}],
      system_prompt: "You are a helpful assistant.",
      track_costs: true
    }

    messages =
      Enum.map(history, fn msg ->
        %LlmComposer.Message{
          type: String.to_existing_atom(msg.role),
          content: msg.content,
          reasoning: msg.reasoning,
          reasoning_details: msg.reasoning_details
        }
      end)

    LlmComposer.run_completion(settings, messages)
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
end
