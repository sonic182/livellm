defmodule Livellm.Repo.Migrations.AddReasoningStepsToMessages do
  use Ecto.Migration

  def change do
    alter table(:messages) do
      add :reasoning_steps, :json
    end
  end
end
