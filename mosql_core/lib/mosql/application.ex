defmodule Mosql.Application do

  @moduledoc false

  use Application

  require Logger

  @impl true
  def start(_type, _args) do
    Logger.info("Mosql application started...")

    children = [
      # start empty, child process is added at runtime
    ]

    opts = [strategy: :one_for_one, name: Mosql.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
