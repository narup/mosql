defmodule MS.Schema do
  alias __MODULE__
  alias Memento.Schema
  alias MS.Schema.Mapping
  alias MS.Store
  alias MS.DB.Schema

  require Logger

  @table "table"
  @columns "columns"
  @sql_column "column"
  @sql_type "type"
  @mongo_key "mongo_key"
  @primary_key "primary_key"
  @primary_keys "primary_keys"
  @mapping "mapping"

  @moduledoc """
  Represents the schema mapping between MongoDB collection and SQL table
  ns is the namespace
  """
  @derive {Poison.Encoder, except: [:description]}
  defstruct ns: "",
            collection: "",
            table: "",
            indexes: [],
            primary_keys: [],
            mappings: [],
            description: ""

  @schema_files_path Application.compile_env!(:mosql, :schema_files_path)

  @typedoc """
  Schema type definition
  """
  @type t :: %__MODULE__{
          ns: String.t(),
          collection: String.t(),
          table: String.t(),
          indexes: term,
          primary_keys: term,
          mappings: term
        }

  @doc """
  Return the saved schema mapping struct
  """
  def saved_mapping(schema) do
    mapping_key(schema, @mapping) |> Store.get()
  end

  @doc """
  Returns the SQL table name for a schema mapping definition
  """
  def table_name(schema) do
    mapping_key(schema, @table) |> Store.get()
  end

  @doc """
  Returns the SQL table column names for a schema mapping definition
  """
  def columns(schema) do
    mapping_key(schema, @columns) |> Store.get()
  end

  @doc """
  Returns the SQL table column type for a schema mapping definition and the given column
  """
  def type(schema, column) do
    mapping_key(schema, column, @sql_type) |> Store.get()
  end

  @doc """
  Returns the mongo document key for a schema mapping definition and the given column
  """
  def mongo_key(schema, column) do
    mapping_key(schema, column, @mongo_key) |> Store.get()
  end

  @doc """
  Returns if the column for a schema mapping is a primary key
  """
  def is_primary_key?(schema, column) do
    mapping_key(schema, column, @primary_key) |> Store.get_if_exists(false)
  end

  @doc """
  Returns the primary key column name
  """
  def primary_key(schema) do
    mapping_key(schema, schema.table, @primary_key) |> Store.get_if_exists("")
  end

  @doc """

  """
  def load_schema_files(namespace, schema_path) do
    Path.wildcard("#{schema_path}/*.json") |> Enum.map(&load_schema_file(namespace, &1))
  end

  def load_schema_file(namespace, path) do
    Logger.info("Loading schema file #{path} for namespace #{namespace}")
    load_schema_file_from_path(path)
  end

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
    load_schema_file_from_path(schema_file_path)
  end

  @doc """
  Load the export schemas from the persistence store based on the export id
  """
  def load_export_schemas(export_id) do
    MS.DB.Schema.read_all(export_id) |> fetch_schema_results()
  end

  defp fetch_schema_results(_ = []), do: {:error, :not_found}

  defp fetch_schema_results(result) do
    ex = Enum.map(result, &from_db(&1)) |> Enum.at(0)
    {:ok, ex}
  end

  defp from_db(db_schema) do
    %MS.Schema{
      ns: db_schema.ns,
      collection: db_schema.collection,
      table: db_schema.table,
      indexes: db_schema.indexes,
      primary_keys: db_schema.primary_keys,
      description: db_schema.description
    }
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
    # Store the whole mapping first in the store
    mapping_key(schema, @mapping) |> Store.set(schema)

    mapping_key(schema, @table) |> Store.set("#{schema.table}")
    mapping_key(schema, @columns) |> Store.set([])

    if Enum.count(schema.primary_keys) > 0 do
      pkeys = Enum.join(schema.primary_keys, ", ")
      mapping_key(schema, @primary_keys) |> Store.set("#{pkeys}")
    end

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

    mapping_key(schema, schema_map_item.sql_column, @primary_key)
    |> Store.set(schema_map_item.primary_key)

    if schema_map_item.primary_key do
      mapping_key(schema, schema.table, @primary_key) |> Store.set(schema_map_item.sql_column)
    end
  end

  defp store_columns(key, schema_map_item) do
    columns = Store.get(key)
    Store.set(key, columns ++ [schema_map_item.sql_column])
  end

  defp mapping_key(schema, field_name) do
    "#{schema.ns}.#{schema.collection}.#{field_name}"
  end

  defp mapping_key(schema, field_name, field_value) do
    "#{schema.ns}.#{schema.collection}.#{field_name}.#{field_value}"
  end

  defp load_schema_file_from_path(schema_file_path) do
    try do
      with {:ok, raw_json} <- File.read(schema_file_path),
           mappings <- Poison.Parser.parse!(raw_json, %{keys: :atoms!}) do
        schema = struct!(Schema, mappings)

        Logger.info("Parsed schema  from file path '#{schema_file_path}'")

        struct_mappings = Enum.map(schema.mappings, &Mapping.to_struct(&1))
        schema = %{schema | mappings: struct_mappings}
        {:ok, schema}
      else
        {:error, :enoent} ->
          {:error, "No such file or directory to read from '#{schema_file_path}'"}
      end
    rescue
      Poison.ParseError ->
        {:error, "JSON parsing failed for schema at file path '#{schema_file_path}"}
    end
  end
end

defmodule MS.Schema.Mapping do
  alias __MODULE__

  @moduledoc """
  Represents the Mongo collection to SQL schema mapping
  """
  @derive [Poison.Encoder]
  defstruct mongo_key: "", sql_column: "", sql_type: "", primary_key: false

  @typedoc """
  Mapping type definition
  """
  @type t :: %__MODULE__{
          mongo_key: String.t(),
          sql_column: String.t(),
          sql_type: String.t(),
          primary_key: boolean()
        }

  def to_struct(values) do
    struct!(Mapping, values)
  end
end

defmodule MS.DB.Schema do
  use Memento.Table,
    attributes: [
      :id,
      :ns,
      :collection,
      :table,
      :indexes,
      :primary_keys,
      :mappings,
      :description,
      :export
    ],
    index: [:export],
    type: :ordered_set,
    autoincrement: true

  def create(opts) do
    Memento.Table.create!(__MODULE__, opts)
  end

  def write(export_id, schema) do
    Memento.transaction!(fn ->
      db_s = to_db(export_id, schema)
      Memento.Query.write(db_s)
    end)
  end

  def read_all(export_id) do
    Memento.transaction!(fn ->
      Memento.Query.select(MS.DB.Schema, {:==, :export, export_id})
    end)
  end

  defp to_db(export_id, schema) do
    %__MODULE__{
      ns: schema.ns,
      collection: schema.collection,
      table: schema.table,
      indexes: schema.indexes,
      primary_keys: schema.primary_keys,
      mappings: schema.mappings,
      description: schema.description,
      export: export_id
    }
  end
end
