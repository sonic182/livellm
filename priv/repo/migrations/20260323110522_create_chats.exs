defmodule Livellm.Repo.Migrations.CreateChats do
  use Ecto.Migration

  def change do
    create table(:chats) do
      add :title, :string, null: false
      add :model, :string, null: false
      add :reasoning_effort, :string
      add :provider_config_id, references(:provider_configs, on_delete: :nilify_all)

      timestamps(type: :utc_datetime)
    end

    create index(:chats, [:provider_config_id])
  end
end
