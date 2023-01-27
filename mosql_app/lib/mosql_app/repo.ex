defmodule MosqlApp.Repo do
  use Ecto.Repo,
    otp_app: :mosql_app,
    adapter: Ecto.Adapters.Postgres
end
