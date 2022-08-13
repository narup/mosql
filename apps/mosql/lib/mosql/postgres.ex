defmodule MS.Postgres do
  def query(query) do
    Postgrex.query!(:postgres, query, [])
  end
end
