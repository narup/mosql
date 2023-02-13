defmodule Mosql.Repo do
  use Ecto.Repo,
    otp_app: :mosql,
    adapter: Ecto.Adapters.Postgres
end
