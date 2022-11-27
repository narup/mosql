defmodule MS.Postgres do
  require Logger

  def query(query) do
    Logger.debug("Executing SQL query: #{query}")
    Postgrex.query(:postgres, query, [])
  end

  def query!(query) do
    Logger.debug("Executing SQL query: #{query}")
    Postgrex.query!(:postgres, query, [])
  end
end
