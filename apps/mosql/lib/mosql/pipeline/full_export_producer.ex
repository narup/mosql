defmodule MS.Pipeline.FullExportProducer do
  use GenStage

  require Logger

  def init(state) do
    Logger.info("Producer init with opts: #{inspect(state)}\n")
    {:producer, state}
  end

  def handle_cast({:trigger, ns}, state) do
    if state.export_triggered do
      Logger.info("Export already triggered, no action performed")
      {:noreply, [], state}
    else
      handle_export_triggred(ns, state)
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

        exported_collections = state.exported_collections ++ demanded
        state = %{state | exported_collections: exported_collections}

        log_state(state)
        {:noreply, demanded, state}

      state.export_triggered == false ->
        state = %{state | pending_demand: demand}

        log_state(state)
        {:noreply, [], state}

      true ->
        log_state(state)
        {:noreply, [], state}
    end
  end

  def trigger(ns) do
    producer_name = Broadway.producer_names(MS.Pipeline.FullExport) |> Enum.random()
    Logger.info("Trigger full export: #{producer_name} for namespace: #{ns}")
    GenStage.cast(producer_name, {:trigger, ns})
  end

  defp handle_export_triggred(ns, state) do
    collections = MS.Schema.all_collections(ns)
    collections = if collections == nil, do: raise("no collections loaded")

    state = %{state | export_triggered: true}

    if Enum.count(collections) > 0 && state.pending_demand > 0 do
      Logger.info("Handling a pending demand of #{state.pending_demand}")
      {demanded, remaining} = Enum.split(collections, state.pending_demand - 1)

      state = %{state | collections: remaining}
      state = %{state | demand_filled: state.pending_demand}
      state = %{state | pending_demand: 0}

      exported_collections = state.exported_collections ++ demanded
      state = %{state | exported_collections: exported_collections}

      log_state(state)
      {:noreply, demanded, state}
    else
      state = %{state | collections: collections}

      log_state(state)
      {:noreply, collections, state}
    end
  end

  defp log_state(state) do
    Logger.info("Full export producer state: #{inspect(state)}")
  end
end
