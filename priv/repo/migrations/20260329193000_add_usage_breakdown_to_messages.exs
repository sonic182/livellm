defmodule Livellm.Repo.Migrations.AddUsageBreakdownToMessages do
  use Ecto.Migration

  def change do
    alter table(:messages) do
      add :usage_breakdown, :json
    end
  end
end
