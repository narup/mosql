defmodule Mosql.Postgres do
  require Logger

  def child_spec(opts) do
    %{
      id: Postgres,
      start: {Postgrex, :start_link, [opts]},
      restart: :transient
    }
  end

  def query(query) do
    Logger.debug("Executing SQL query: #{query}")
    Postgrex.query(:postgres, query, [])
  end

  def query!(query) do
    Logger.debug("Executing SQL query: #{query}")
    Postgrex.query!(:postgres, query, [])
  end
end
