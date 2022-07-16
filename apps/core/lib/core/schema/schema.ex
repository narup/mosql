defmodule MS.Core.Schema do
  alias __MODULE__
  alias MS.Core.Schema.Mapping
  alias MS.Core.Schema.Store

  require Logger

  @sql_column "column"
  @sql_type "type"
  @mongo_key "mongo_key"

  @moduledoc """
  Represents the schema mapping between MongoDB collection and SQL table
  ns is the namespace
  """
  defstruct ns: "", collection: "", table: "", indexes: [], mappings: []

  @schema_files_path Application.fetch_env!(:core, :schema_files_path)

  @typedoc """
  Schema type definition
  """
  @type t :: %__MODULE__{
          ns: String.t(),
          collection: String.t(),
          table: String.t(),
          indexes: term,
          mappings: term
        }

  @doc """
  Creates a schema struct based on the collection schema definition, which is a JSON
  that defines the mapping between MongoDB collection and the SQL table definition
  """
  def load_collection(collection) do
    schema_file_path =
      @schema_files_path
      |> Path.join("#{collection}.json")
      |> Path.absname()

    Logger.info("Schema file path for collection '#{collection}' is '#{schema_file_path}'")

    try do
      with {:ok, raw_json} <- File.read(schema_file_path),
           mappings <- Poison.Parser.parse!(raw_json, %{keys: :atoms!}) do
        schema = struct!(Schema, mappings)

        Logger.info(
          "Parsed schema for collection '#{collection}' from file path '#{schema_file_path}'"
        )

        struct_mappings = Enum.map(schema.mappings, &Mapping.to_struct(&1))
        schema = %{schema | mappings: struct_mappings}
        {:ok, schema}
      else
        {:error, :enoent} ->
          {:error, "Schema file not found for collection '#{collection}'"}
      end
    rescue
      Poison.ParseError ->
        {:error, "JSON parsing failed for collection '#{collection}"}
    end
  end

  @doc """
  store the schema mapping as key value in the Schema store
    <namespace>.<collection>.table = <value>
    <namespace>.<collection>.columns = [values...]
    <namespace>.<collection>.<mongo_key>.indexes = [values...]
    <namespace>.<collection>.<mongo_key>.column = <value>
    <namespace>.<collection>.<mongo_key>.type = <value>
    <namespace>.<collection>.<sql_column>.type = <value>
    <namespace>.<collection>.<sql_column>.mongo_key = <value>
  """
  def populate_schema_store(schema) do
    mapping_key(schema, "table") |> Store.set("#{schema.table}")
    mapping_key(schema, "columns") |> Store.set([])

    store_mappings(schema)
  end

  defp store_mappings(schema) do
    Enum.each(schema.mappings, &store_map_items(schema, &1))
  end

  defp store_map_items(schema, schema_map_item) do
    store_columns("#{schema.ns}.#{schema.collection}.columns", schema_map_item)

    mapping_key(schema, schema_map_item.mongo_key, @sql_column)
    |> Store.set(schema_map_item.sql_column)

    mapping_key(schema, schema_map_item.mongo_key, @sql_type)
    |> Store.set(schema_map_item.sql_type)

    mapping_key(schema, schema_map_item.sql_column, @sql_type)
    |> Store.set(schema_map_item.sql_type)

    mapping_key(schema, schema_map_item.sql_column, @mongo_key)
    |> Store.set(schema_map_item.mongo_key)
  end

  defp store_columns(key, schema_map_item) do
    columns = Store.get(key)
    Store.set(key, columns ++ [schema_map_item.sql_column])
  end

  def mapping_key(schema, field_name) do
    "#{schema.ns}.#{schema.collection}.#{field_name}"
  end

  def mapping_key(schema, field_name, field_value) do
    "#{schema.ns}.#{schema.collection}.#{field_name}.#{field_value}"
  end
end

defmodule MS.Core.Schema.Mapping do
  alias __MODULE__

  @moduledoc """
  Represents the Mongo collection to SQL schema mapping
  """
  defstruct mongo_key: "", sql_column: "", sql_type: ""

  @typedoc """
  Mapping type definition
  """
  @type t :: %__MODULE__{
          mongo_key: String.t(),
          sql_column: String.t(),
          sql_type: String.t()
        }

  def to_struct(values) do
    struct!(Mapping, values)
  end
end

defmodule MS.Core.Schema.SQL do
  require Logger

  alias MS.Core.Schema
  alias MS.Core.Schema.Store

  @doc """
    Generates a SQL string for creating a table

    CREATE TABLE [IF NOT EXISTS] table_name (
      column1 datatype(length) column_contraint,
      column2 datatype(length) column_contraint,
      column3 datatype(length) column_contraint,
      ...
      table_constraints
    );

  """
  def create_table(schema) do
    Logger.info("Generating table creation SQL for #{schema.ns}.#{schema.collection}")

    table_name = Schema.mapping_key(schema, "table") |> Store.get()
    header = "CREATE TABLE IF NOT EXISTS #{schema.ns}.#{table_name} ("
    tail = ");"

    Logger.info("header: #{header}")
  end

end
