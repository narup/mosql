defmodule MosqlWeb.Repo do
  use Ecto.Repo,
    otp_app: :mosql_web,
    adapter: Ecto.Adapters.Postgres
end
