defmodule Livellm.Repo.Migrations.CreateProviderConfigs do
  use Ecto.Migration

  def change do
    create table(:provider_configs) do
      add :provider, :string, null: false
      add :label, :string, null: false
      add :api_key, :string
      add :default_model, :string
      add :base_url, :string
      add :enabled, :boolean, default: false, null: false

      timestamps(type: :utc_datetime)
    end
  end
end
