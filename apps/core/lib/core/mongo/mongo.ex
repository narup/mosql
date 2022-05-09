defmodule MS.Core.Mongo do
  @doc """
  checks if the mongo connection is alive
  """
  def is_alive?() do
    case Mongo.ping(:mongo) do
      {:ok, %{"ok" => 1}} -> true
      _ -> false
    end
  end

  def documents(collection, query) do
    Mongo.find(:mongo, collection, query) |> Enum.to_list()
  end

  def insert(_collection, data) when is_nil(data), do: {:error, "no data"}

  def insert(collection, data) when length(data) == 1 do
    Mongo.insert_one(:mongo, collection, Enum.at(data, 0))
  end

  def insert(collection, data) when length(data) > 0 do
    Mongo.insert_many(:mongo, collection, data)
  end
end
