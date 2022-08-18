defmodule MS do
  @moduledoc """
  Documentation for `MS`.
  """

  alias MS.Mongo
  alias MS.Schema
  alias MS.Schema.{SQL, Mapping}
  alias MS.Export

  require Logger

  @doc """
  creates the complete postgres type export definition for the given namespace
  """
  def create_postgres_export(namespace) do
    case Export.new(namespace, "postgres") do
      :already_exists ->
        export = Export.fetch(namespace, "postgres")
        populate_export_schemas(export)

      export ->
        populate_export_schemas(export)
    end
  end

  @doc """
  Load all the schema definition from the given export to the schema store. This function has
  to be called before we start the export process
  """
  def store_export_schemas(export) do
    export.schemas |> Enum.each(&Schema.populate_schema_store(&1))
  end

  defp populate_export_schemas(export) do
    schemas = Mongo.collections() |> Enum.map(&generate_schema_map(export.ns, &1))
    %{export | schemas: schemas}
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
