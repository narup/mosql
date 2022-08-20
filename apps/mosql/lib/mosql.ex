defmodule MS.Base do
  @moduledoc """
  Documentation for `MS`.
  """

  alias MS.Mongo
  alias MS.Schema
  alias MS.Schema.{SQL, Mapping}
  alias MS.Export

  require Logger

  @type_postgres "postgres"

  @doc """
  creates the complete postgres type export definition for the given namespace
  """
  def create_postgres_export(namespace, options \\ []) do
    case Export.new(namespace, @type_postgres, options) do
      {:ok, export} ->
        populate_export_schemas(export)

      {:error, :already_exists} ->
        Logger.info("Export already exists. Genera")
        Export.fetch(namespace, @type_postgres)
    end
  end

  @doc """
  Populate the given export schemas with schema definition based on the
  collection list and export definition
  """
  def populate_export_schemas(export) do
    schemas = final_collection_list(export) |> Enum.map(&generate_schema_map(export.ns, &1))
    export = %{export | schemas: schemas}
    Export.update(export.ns, export.type, export)
  end

  @doc """
  Load all the schema definition from the given export to the schema store.
  This function has to be called before we start the export process
  """
  def store_export_schemas(export) do
    export.schemas |> Enum.each(&Schema.populate_schema_store(&1))
  end

  defp final_collection_list(export) do
    collections = Mongo.collections()

    cond do
      Export.has_exclusives?(export) > 0 -> filter_exclusives(collections, export.exclusives)
      Export.has_exclusions?(export) > 0 -> filter_exclusions(collections, export.exclusions)
      true -> collections
    end
  end

  ## good to loop over actual collections to avoid typos on exclusives
  defp filter_exclusives(collections, exclusives) do
    Enum.filter(collections, &Enum.member?(exclusives, &1))
  end

  ## good to loop over actual collections to avoid typos on exclusives
  defp filter_exclusions(collections, exclusions) do
    Enum.filter(collections, fn coll -> Enum.member?(exclusions, coll) == false end)
  end

  @doc """
  Generate  a default schema mapping for a collection based on the given collection name
  """
  def generate_schema_map(namespace, collection) do
    Logger.info("Generating schema for namespace #{namespace} and collection #{collection}")

    schema = %Schema{
      ns: namespace,
      collection: collection,
      table: Macro.underscore(collection),
      indexes: [],
      primary_keys: [],
      mappings: []
    }

    flat_document = Mongo.flat_collection(collection)

    mappings = flat_document |> Map.keys() |> generate_mappings(flat_document)
    %{schema | mappings: mappings}
  end

  defp generate_mappings(keys, flat_document) do
    Enum.map(keys, &generate_field_mapping(&1, flat_document))
  end

  defp generate_field_mapping(key, flat_document) do
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
    mongo_type = MS.Mongo.Type.typeof(val)
    SQL.mongo_to_sql_type(mongo_type)
  end

  defp key_to_column_name(_ = "_id"), do: "id"

  defp key_to_column_name(key) do
    Macro.underscore(key) |> String.replace("/", "_")
  end
end
