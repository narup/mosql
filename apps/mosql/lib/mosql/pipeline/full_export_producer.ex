defmodule MS.Pipeline.FullExportProducer do
  use GenStage

  require Logger

  def init(opts) do
    Logger.info("Producer init with opts: #{inspect(opts)}\n")
    {:producer, opts}
  end

  def handle_cast({:trigger, ns}, counter) do
    Logger.info("Starting full data export for namespace: #{ns}")
    events = ["1", "2", "3", "4", "5", "6", "7", "8", "9", "0"]
    {:noreply, events, counter + 10}
  end

  def handle_demand(demand, counter) do
    IO.puts("Counter: #{counter}. Demand: #{demand}")
    {:noreply, [], counter + demand}
  end

  def trigger(ns) do
    producer_name = Broadway.producer_names(MS.Pipeline.FullExport) |> Enum.random()
    Logger.info("Trigger full export: #{producer_name} for namespace: #{ns}")
    GenStage.cast(producer_name, {:trigger, ns})
  end
end
