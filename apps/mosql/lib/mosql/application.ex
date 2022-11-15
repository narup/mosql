defmodule MS.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  require Logger

  @impl true
  def start(_type, _args) do
    Logger.info("MS.Application started...")

    mongo_opts = Application.fetch_env!(:mosql, :mongo_opts)
    postgres_opts = Application.fetch_env!(:mosql, :postgres_opts)

    children = [
      {Mongo, mongo_opts},
      {Postgrex, postgres_opts},
      {MS.Store, []},
      #{MS.Pipeline.ChangeStream, []},
      {MS.Pipeline.FullExport, []}
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: MS.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
