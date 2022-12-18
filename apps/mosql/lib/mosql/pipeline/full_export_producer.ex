defmodule MS.Pipeline.FullExportProducer do
  use GenStage

  require Logger

  def init(opts) do
    Logger.info("Producer init with opts: #{inspect(opts)}\n")
    {:producer, opts}
  end

  def handle_cast({:trigger, ns}, state) do
    collections = MS.Schema.all_collections(ns)
    state = %{state | export_triggered: true}

    if state.pending_demand > 0 do
      Logger.info("Handling a pending demand of #{state.pending_demand}")
      {demanded, remaining} = Enum.split(collections, state.pending_demand - 1)

      state = %{state | collections: remaining}
      state = %{state | demand_filled: state.pending_demand}
      state = %{state | pending_demand: 0}

      {:noreply, demanded, state}
    else
      state = %{state | collections: collections}
      {:noreply, collections, state}
    end
  end

  def handle_demand(demand, state) do
    Logger.info("Demand received for #{demand} collections")

    cond do
      state.export_triggered && Enum.count(state.collections) == 0 ->
        Logger.info("No collections pending for the requested demand")
        {:noreply, [], state}

      state.export_triggered && Enum.count(state.collections) > 0 ->
        {demanded, remaining} = Enum.split(state.collections, demand - 1)
        state = %{state | collections: remaining}

        demand_filled = state[:demand_filled] + demand
        state = %{state | demand_filled: demand_filled}

        {:noreply, demanded, state}

      state.export_triggered == false ->
        state = %{state | pending_demand: demand}
        {:noreply, [], state}

      true ->
        {:noreply, [], state}
    end
  end

  def trigger(ns) do
    producer_name = Broadway.producer_names(MS.Pipeline.FullExport) |> Enum.random()
    Logger.info("Trigger full export: #{producer_name} for namespace: #{ns}")
    GenStage.cast(producer_name, {:trigger, ns})
  end
end
