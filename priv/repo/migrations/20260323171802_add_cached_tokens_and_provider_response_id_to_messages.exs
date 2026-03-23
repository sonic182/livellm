defmodule Livellm.Repo.Migrations.AddCachedTokensAndProviderResponseIdToMessages do
  use Ecto.Migration

  def change do
    alter table(:messages) do
      add :cached_tokens, :integer
      add :provider_response_id, :string
    end
  end
end
