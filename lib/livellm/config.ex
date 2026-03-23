defmodule Livellm.Config do
  @moduledoc """
  Context for managing LLM provider configurations.
  """

  import Ecto.Query

  alias Livellm.Config.ProviderConfig
  alias Livellm.Repo

  def list_provider_configs do
    Repo.all(from c in ProviderConfig, order_by: c.inserted_at)
  end

  def get_provider_config!(id), do: Repo.get!(ProviderConfig, id)

  def change_provider_config(%ProviderConfig{} = config, attrs \\ %{}) do
    ProviderConfig.changeset(config, attrs)
  end

  def create_provider_config(attrs) do
    %ProviderConfig{}
    |> ProviderConfig.changeset(attrs)
    |> Repo.insert()
  end

  def delete_provider_config(%ProviderConfig{} = config), do: Repo.delete(config)

  def set_enabled(%ProviderConfig{} = config) do
    Repo.transaction(fn ->
      Repo.update_all(ProviderConfig, set: [enabled: false])
      Repo.update!(ProviderConfig.changeset(config, %{enabled: true}))
    end)
  end
end
