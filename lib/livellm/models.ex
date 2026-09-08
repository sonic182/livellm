defmodule Livellm.Models do
  @moduledoc """
  Lists the models a provider exposes on its catalog endpoint (`/models` for the
  OpenAI-compatible providers, `/api/tags` for Ollama).

  Results are cached in the ETS cache that `llm_composer` already supervises, so the
  chat header can ask for them on every provider change without hitting the network.
  """

  alias LlmComposer.Cache.Ets

  require Logger

  @cache_ttl_seconds 3600
  @timeout 5_000

  @spec list(map() | nil) :: [String.t()]
  def list(nil), do: []

  def list(config) do
    key = cache_key(config)

    case Ets.get(key) do
      {:ok, models} ->
        models

      _miss ->
        models = if fetch_enabled?(), do: fetch(config), else: []
        if models != [], do: Ets.put(key, models, @cache_ttl_seconds)
        models
    end
  end

  @doc """
  Case-insensitive substring filter, used by the model combobox.
  """
  @spec filter([String.t()], String.t() | nil, pos_integer()) :: [String.t()]
  def filter(models, query, limit \\ 50)
  def filter(models, query, limit) when query in [nil, ""], do: Enum.take(models, limit)

  def filter(models, query, limit) do
    query = String.downcase(query)

    models
    |> Enum.filter(&String.contains?(String.downcase(&1), query))
    |> Enum.take(limit)
  end

  # --- Private ---

  defp cache_key(config), do: "livellm_models:#{config.provider}:#{config.base_url}"

  # Disabled in the test env so mounting the chat never reaches a provider.
  defp fetch_enabled?, do: Application.get_env(:livellm, :fetch_provider_models, true)

  defp fetch(config) do
    case Req.get(endpoint(config), headers: headers(config), receive_timeout: @timeout) do
      {:ok, %{status: 200, body: body}} ->
        extract(body)

      {:ok, %{status: status}} ->
        Logger.warning("[models] #{config.provider} catalog returned status=#{status}")
        []

      {:error, reason} ->
        Logger.warning("[models] #{config.provider} catalog failed: #{inspect(reason)}")
        []
    end
  end

  defp endpoint(%{provider: "ollama"} = config) do
    base(config, "http://localhost:11434") <> "/api/tags"
  end

  defp endpoint(%{provider: "google"} = config) do
    base(config, "https://generativelanguage.googleapis.com/v1beta") <> "/models"
  end

  defp endpoint(%{provider: "openrouter"} = config) do
    base(config, "https://openrouter.ai/api/v1") <> "/models"
  end

  defp endpoint(config) do
    base(config, "https://api.openai.com/v1") <> "/models"
  end

  defp base(%{base_url: base_url}, _default) when is_binary(base_url) and base_url != "" do
    String.trim_trailing(base_url, "/")
  end

  defp base(_config, default), do: default

  defp headers(%{provider: "google", api_key: key}) when is_binary(key) and key != "",
    do: [{"x-goog-api-key", key}]

  defp headers(%{api_key: key}) when is_binary(key) and key != "",
    do: [{"authorization", "Bearer " <> key}]

  defp headers(_config), do: []

  # `data` for the OpenAI-compatible catalogs, `models` for Ollama and Google.
  defp extract(%{"data" => entries}) when is_list(entries), do: names(entries)
  defp extract(%{"models" => entries}) when is_list(entries), do: names(entries)
  defp extract(_body), do: []

  defp names(entries) do
    entries
    |> Enum.map(&name/1)
    |> Enum.reject(&(&1 in [nil, ""]))
    |> Enum.uniq()
    |> Enum.sort()
  end

  defp name(%{"id" => id}) when is_binary(id), do: id
  # Google reports `models/gemini-3-pro`, Ollama reports the plain tag.
  defp name(%{"name" => name}) when is_binary(name),
    do: String.replace_prefix(name, "models/", "")

  defp name(_entry), do: nil
end
