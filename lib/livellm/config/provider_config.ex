defmodule Livellm.Config.ProviderConfig do
  use Ecto.Schema
  import Ecto.Changeset

  schema "provider_configs" do
    field :provider, :string
    field :label, :string
    field :api_key, :string
    field :default_model, :string
    field :base_url, :string
    field :enabled, :boolean, default: false

    timestamps(type: :utc_datetime)
  end

  @required [:provider, :label]
  @optional [:api_key, :default_model, :base_url, :enabled]

  @doc false
  def changeset(provider_config, attrs) do
    provider_config
    |> cast(attrs, @required ++ @optional)
    |> validate_required(@required)
    |> validate_inclusion(:provider, ["openai", "openrouter", "ollama", "google"])
    |> validate_length(:default_model, min: 1)
  end
end
