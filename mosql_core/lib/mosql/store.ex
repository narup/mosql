defmodule Mosql.Store do
  use Agent

  require Logger

  @moduledoc """
  Agent based key value store to store schema mapping between mongo collection and
  SQL table
  """
  def start_link(_) do
    Logger.info("Starting schema store using Agent")
    Agent.start_link(fn -> %{} end, name: __MODULE__)
  end

  def set(key, value) do
    Agent.update(__MODULE__, &Map.put(&1, key, value))
  end

  def get(key) do
    Agent.get(__MODULE__, fn state ->
      case Map.fetch(state, key) do
        {:ok, r} -> r
        :error -> nil
      end
    end)
  end

  def get_if_exists(key, default_val) do
    Agent.get(__MODULE__, &Map.get(&1, key, default_val))
  end

  def get_all_keys() do
    Agent.get(__MODULE__, &Map.keys/1)
  end
end
