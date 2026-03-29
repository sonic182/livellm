defmodule Livellm.Repo.Migrations.AddToolCallsToMessages do
  use Ecto.Migration

  def change do
    alter table(:messages) do
      add :tool_calls, {:array, :map}
    end
  end
end
