defmodule Livellm.Repo.Migrations.AddMessageCostTracking do
  use Ecto.Migration

  def change do
    alter table(:messages) do
      add :input_tokens, :integer
      add :output_tokens, :integer
      add :total_tokens, :integer
      add :input_cost, :decimal, precision: 20, scale: 8
      add :output_cost, :decimal, precision: 20, scale: 8
      add :total_cost, :decimal, precision: 20, scale: 8
      add :cost_currency, :string
      add :provider_name, :string
      add :provider_model, :string
    end
  end
end
