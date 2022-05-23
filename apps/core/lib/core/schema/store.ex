defmodule MS.Core.Schema.Store do
  use Agent

  require Logger

  @moduledoc """
  Agent based key value store to store schema mapping between mongo collection and
  SQL table
  """
  def start_link(initial_value) do
    Logger.info("Starting schema store using Agent")
    Agent.start_link(fn -> initial_value end, name: __MODULE__)
  end

  def set(key, value) do
    Agent.update(__MODULE__, &Map.put(&1, key, value))
  end

  def get(key) do
    Agent.get(__MODULE__, &Map.fetch!(&1, key))
  end
end
