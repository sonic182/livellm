defmodule Livellm.Repo.Migrations.AddMemoryAndTraceFields do
  use Ecto.Migration

  def change do
    create table(:user_memories) do
      add :title, :string, null: false
      add :content, :string, null: false

      timestamps(type: :utc_datetime)
    end

    alter table(:messages) do
      add :tool_calls, {:array, :map}
      add :reasoning_steps, :json
      add :usage_breakdown, :json
    end
  end
end
