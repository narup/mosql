defmodule MS.Mongo do
  alias MS.Mongo.{Document, Type}

  @doc """
  checks if the mongo connection is alive
  """
  def is_alive?() do
    case Mongo.ping(:mongo) do
      {:ok, %{"ok" => 1}} -> true
      _ -> false
    end
  end

  @doc """
  Returns a cursor for all the documents for a given collection
  with a given batch size
  """
  def find_all(collection, batch_size) do
    Mongo.find(:mongo, collection, %{}, batch_size: batch_size, limit: 400)
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

  def collections() do
    Mongo.show_collections(:mongo)
  end

  @doc """
  Extracts all the keys of the collection. If there are embedded fields within the collection
  it uses the dot notation to construct the key. E.g. parentField.embeddedField.childField
  """
  def collection_keys(collection, opts \\ []) do
    Mongo.find_one(:mongo, collection, %{}, opts) |> extract_document_keys()
  end

  def flat_collection(collection, opts \\ []) do
    Mongo.find_one(:mongo, collection, %{}, opts) |> flat_document_map()
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
    string_id = Document.string_id(document["_id"])
    document = %{document | "_id" => string_id}

    document |> to_list() |> to_flat_map()
  end

  @doc """
  Extract only the list of keys in a document for the given document
  """
  def extract_document_keys(document) do
    flat_document_map(document) |> Map.keys()
  end

  defp to_list(map) when is_map(map) do
    Enum.map(map, &break_map(&1))
  end

  # If the value is a list then it needs special handling
  # based on the values contained in the list. If the values
  # in the list are simple types, then just merge them to a
  # string with comma separated values. If the values are complex
  # types then it converts them to a JSON blob
  defp to_list(list) when is_list(list) do
    if Enum.all?(list, &simple_type/1) do
      Enum.join(list, ",")
    else
      result = Enum.reduce(list, [], fn item, acc -> acc ++ [Poison.encode!(item)] end)
      result = Enum.join(result, ",")
      "[" <> result <> "]"
    end
  end

  defp simple_type(v) do
    is_bitstring(v) || is_float(v) || is_integer(v) || is_binary(v)
  end

  defp break_map({k, v}) do
    cond do
      Type.typeof(v) == "map" -> {k, to_list(v)}
      Type.typeof(v) == "list" -> {k, to_list(v)}
      true -> {k, v}
    end
  end

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

defmodule MS.Mongo.Document do
  def string_id(object_id) do
    BSON.ObjectId.encode!(object_id)
  end
end

defmodule MS.Mongo.Type do
  def typeof(%DateTime{} = _), do: "datetime"
  def typeof(a) when is_boolean(a), do: "boolean"
  def typeof(a) when is_map(a), do: "map"
  def typeof(a) when is_list(a), do: "list"
  def typeof(a) when is_bitstring(a), do: "string"
  def typeof(a) when is_float(a), do: "float"

  def typeof(a) when is_integer(a) do
    cond do
      a <= 99999 -> "small_integer"
      a > 99999 && a <= 9_999_999_999 -> "integer"
      a > 9_999_999_999 -> "big_integer"
    end
  end

  def typeof(a) when is_binary(a), do: "binary"
  def typeof(a) when is_tuple(a), do: "tuple"
  def typeof(a) when is_atom(a), do: "atom"
end
