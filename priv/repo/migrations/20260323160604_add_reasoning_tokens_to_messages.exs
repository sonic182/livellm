defmodule Livellm.Repo.Migrations.AddReasoningTokensToMessages do
  use Ecto.Migration

  def change do
    alter table(:messages) do
      add :reasoning_tokens, :integer
    end
  end
end
