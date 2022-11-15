defmodule MS.Pipeline.FullExportProducer do
  use GenStage

  require Logger

  def init(opts) do
    Logger.info("Producer init with opts: #{inspect(opts)}\n")
    {:producer, opts}
  end

  def handle_cast(:trigger, counter) do
    Logger.info("Starting data export")
    events = ["1", "2", "3", "4", "5", "6", "7", "8", "9", "0"]
    {:noreply, events, counter + 10}
  end

  def handle_demand(demand, counter) do
    IO.puts("Counter: #{counter}. Demand: #{demand}")
    {:noreply, [], counter + demand}
  end

  def trigger() do
    producer_name = Broadway.producer_names(MS.Pipeline.FullExport) |> Enum.random()
    Logger.info("Producer name: #{producer_name}")
    GenStage.cast(producer_name, :trigger)
  end
end
