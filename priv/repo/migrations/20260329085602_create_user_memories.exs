defmodule Livellm.Repo.Migrations.CreateUserMemories do
  use Ecto.Migration

  def change do
    create table(:user_memories) do
      add :title, :string, null: false
      add :content, :string, null: false

      timestamps(type: :utc_datetime)
    end
  end
end
