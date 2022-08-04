defmodule MS.Core do
  @moduledoc """
  Documentation for `MS.Core`.
  """

  alias MS.Core.Mongo
  alias MS.Core.Schema
  alias MS.Core.Schema.Mapping

  @doc """
  Generate  a default schema mapping for a collection based on the given collection name
  """
  def generate_schema(collection) do
    schema = %Schema{
      ns: "mosql",
      collection: collection,
      table: Macro.underscore(collection),
      indexes: [],
      primary_keys: [],
      mappings: []
    }

    mappings = Mongo.collection_keys(collection) |> Enum.map(&generate_field_mapping(&1))
    %{schema | mappings: mappings}
  end

  def generate_field_mapping(key) do
    %Mapping{
      mongo_key: key,
      sql_column: key_to_column_name(key),
      sql_type: "text",
      primary_key: false
    }
  end

  def key_to_column_name(_ = "_id"), do: "id"
  def key_to_column_name(key) do
    Macro.underscore(key) |> String.replace("/", "_")
  end

end
