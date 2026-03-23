defmodule Livellm.Repo do
  use Ecto.Repo,
    otp_app: :livellm,
    adapter: Ecto.Adapters.SQLite3
end
