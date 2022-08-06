defmodule MS.Core do
  @moduledoc """
  Documentation for `MS.Core`.
  """

  alias MS.Core.Mongo
  alias MS.Core.Schema
  alias MS.Core.Schema.{SQL, Mapping}

  @doc """
  Generates and loads the schema mapping to the schema mapping store for MongoDB collection to SQL data
  translation. Both schema struct and the mapping key/values are stored in the MS.Core.Schema.Store
  """
  def load_collection_mapping(collection) do
    schema = generate_schema_map(collection)
    Schema.populate_schema_store(schema)
    {:ok, schema}
  end

  @doc """
  Generate  a default schema mapping for a collection based on the given collection name
  """
  def generate_schema_map(collection) do
    schema = %Schema{
      ns: "mosql",
      collection: collection,
      table: Macro.underscore(collection),
      indexes: [],
      primary_keys: [],
      mappings: []
    }

    flat_document = Mongo.flat_collection(collection)
    IO.inspect(flat_document)

    mappings = flat_document |> Map.keys() |> generate_mappings(flat_document)
    %{schema | mappings: mappings}
  end

  def generate_mappings(keys, flat_document) do
    Enum.map(keys, &generate_field_mapping(&1, flat_document))
  end

  def generate_field_mapping(key, flat_document) do
    sql_type = extract_sql_type(key, flat_document)
    sql_column = key_to_column_name(key)
    field_mapping_for_key(key, sql_column, sql_type)
  end

  defp field_mapping_for_key(key = "_id", sql_column, sql_type) do
    %Mapping{
      mongo_key: key,
      sql_column: sql_column,
      sql_type: sql_type,
      primary_key: true
    }
  end

  defp field_mapping_for_key(key, sql_column, sql_type) do
    %Mapping{
      mongo_key: key,
      sql_column: sql_column,
      sql_type: sql_type
    }
  end

  defp extract_sql_type(key, flat_document) do
    val = Map.get(flat_document, key)
    mongo_type = MS.Core.Mongo.Type.typeof(val)
    SQL.mongo_to_sql_type(mongo_type)
  end

  defp key_to_column_name(_ = "_id"), do: "id"

  defp key_to_column_name(key) do
    Macro.underscore(key) |> String.replace("/", "_")
  end
end
