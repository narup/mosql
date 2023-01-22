defmodule Mosql.Application do

  @moduledoc false

  use Application

  require Logger

  @impl true
  def start(_type, _args) do
    Logger.info("Mosql.Application started...")

    mongo_opts = Application.fetch_env!(:mosql, :mongo_opts)
    postgres_opts = Application.fetch_env!(:mosql, :postgres_opts)

    children = [
      {Mongo, mongo_opts},
      {Postgrex, postgres_opts},
      {Mosql.Store, []},
      {Mosql.ChangeStreamExport, []},
      {Mosql.FullExport, []}
    ]

    opts = [strategy: :one_for_one, name: Mosql.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
