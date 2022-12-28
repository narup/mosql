defmodule MS.Pipeline.FullExportProducer do
  use GenStage

  require Logger

  @doc """
  Trigger the full export process. This starts the Broadway producer
  """
  def trigger(ns) do
    Logger.info("Triggered full export for namespace #{ns}")
    producer() |> GenStage.cast({:trigger, ns})
  end

  def info_producer_status(ns) do
    producer() |> GenStage.cast({:status_info, ns})
  end

  @impl true
  def init(state) do
    Logger.info("Producer init with opts: #{inspect(state)}\n")
    {:producer, state}
  end

  @impl true
  def handle_cast({:trigger, ns}, state) do
    if state.export_triggered do
      Logger.info("Export already triggered, no action performed")
      {:noreply, [], state}
    else
      handle_export_triggred(ns, state)
    end
  end

  @impl true
  def handle_cast({:status_info, ns}, state) do
    log_state(state)
    Logger.info("Status logged for full export for namespace #{ns}")
    {:noreply, [], state}
  end

  @impl true
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

        final_list = collection_data(state.namespace, demanded)
        {:noreply, final_list, state}

      state.export_triggered == false ->
        state = %{state | pending_demand: demand}

        log_state(state)
        {:noreply, [], state}

      true ->
        log_state(state)
        {:noreply, [], state}
    end
  end

  defp handle_export_triggred(ns, state) do
    collections = MS.Schema.all_collections(ns)
    if collections == nil, do: raise("no collections loaded")

    Logger.info("Total collections to export #{inspect(Enum.count(collections))}")

    state = %{state | export_triggered: true}
    state = %{state | namespace: ns}

    if Enum.count(collections) > 0 && state.pending_demand > 0 do
      Logger.info("Handling a pending demand of #{state.pending_demand}")
      {demanded, remaining} = Enum.split(collections, state.pending_demand - 1)

      state = %{state | collections: remaining}
      state = %{state | demand_filled: state.pending_demand}
      state = %{state | pending_demand: 0}

      exported_collections = state.exported_collections ++ demanded
      state = %{state | exported_collections: exported_collections}

      log_state(state)

      final_list = collection_data(state.namespace, demanded)
      {:noreply, final_list, state}
    else
      state = %{state | collections: collections}

      log_state(state)

      final_list = collection_data(state.namespace, collections)
      {:noreply, final_list, state}
    end
  end

  defp producer() do
    Broadway.producer_names(MS.Pipeline.FullExport) |> Enum.random()
  end

  defp log_state(state) do
    Logger.info("Full export producer state: #{inspect(state)}")
  end

  defp collection_data(ns, collections) do
    Enum.map(collections, fn c ->
      [namespace: ns, collection: c]
    end)
  end
end
