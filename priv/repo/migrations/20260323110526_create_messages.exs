defmodule Livellm.Repo.Migrations.CreateMessages do
  use Ecto.Migration

  def change do
    create table(:messages) do
      add :role, :string, null: false
      add :content, :string
      add :reasoning, :string
      add :reasoning_details, {:array, :map}
      add :raw_response, :map
      add :provider_messages, :map
      add :chat_id, references(:chats, on_delete: :delete_all), null: false

      timestamps(type: :utc_datetime)
    end

    create index(:messages, [:chat_id])
  end
end
