defmodule MS.Core.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    mongo_opts = Application.fetch_env!(:core, :mongo_opts)
    mongo_opts = Keyword.put(mongo_opts, :name, :mongo)

    children = [
      MS.Repo,
      {Mongo, mongo_opts}
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: MS.Core.Supervisor]
    Supervisor.start_link(children, opts)
  end
end