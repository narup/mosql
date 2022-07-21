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

  def collection_keys(collection, opts \\[]) do
    Mongo.find(:mongo, collection, %{}, opts) |> extract_document_keys()
  end

  @doc """
  Converts the mongo document map structure to flat key value pair.
  For example:

  Input Mongo Document:
  %{
    "_id" => "BSON.ObjectId<6277f677b99d8078d17d5918>",
    "attributes" => %{
      "communicationChannels" => %{
        "email" => "hello@mosql.io",
        "phone" => "111222333"
      },
      "communicationPrefs" => "SMS",
      "phoneNumberVerified" => true,
      "randomAttributes" => %{
        "app_source" => "web",
        "channel" => "marketing",
        "signup_complete" => "false"
      },
      "skipTutorial" => false,
      "themeAttributes" => %{
        "appearance" => "dark",
        "automatic" => false,
        "color" => "#cc00ff"
      }
    },
    "city" => "San Francisco",
    "email" => "hello@mosql.io",
    "state" => "CA"
  }

  Output:
  %{
    "_id": "BSON.ObjectId<6277f677b99d8078d17d5918>",
    "attributes.communicationChannels.email": "hello@mosql.io",
    "attributes.communicationChannels.phone": "111222333",
    "attributes.communicationPrefs": "SMS",
    "attributes.phoneNumberVerified": true,
    "attributes.randomAttributes.app_source": "web",
    ...
    .....
    "city": "San Francisco",
    "state: "CA"
  }

  """
  def flat_document_map(document) do
    document |> to_list() |> to_flat_map()
  end

  @doc """
  Extract only the list of keys in a document for the given document
  """
  def extract_document_keys(document) do
    flat_document_map(document) |> Map.keys()
  end

  defp to_list(map) when is_map(map), do: Enum.map(map, fn {k, v} -> {k, to_list(v)} end)
  defp to_list(v), do: v

  defp to_flat_map(list, parent_key \\ "") do
    Enum.reduce(list, %{}, fn {key, val}, acc ->
      new_key = compound_key(key, parent_key)
      acc_map(new_key, val, acc)
    end)
  end

  defp acc_map(new_key, val, acc) do
    cond do
      is_list(val) ->
        map = to_flat_map(val, new_key)
        Map.merge(acc, map)

      true ->
        Map.put(acc, new_key, val)
    end
  end

  defp compound_key(key, _ = ""), do: key
  defp compound_key(key, parent_key), do: "#{parent_key}.#{key}"
end
