defmodule Mosql.ExportSupervisor do
  use Supervisor

  require Logger

  def start_link(init_arg) do
    Logger.info("Mosql.ExportSupervisor started")
    Supervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

  @impl true
  def init(_init_arg) do
    children = [
      # added dynamically at runtime
    ]

    Supervisor.init(children, strategy: :one_for_one, restart: :transient)
  end
end
