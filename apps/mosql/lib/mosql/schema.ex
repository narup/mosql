defmodule MS.Schema do
  alias __MODULE__
  alias MS.Schema.Mapping
  alias MS.Store

  require Logger

  @name "name"
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
            name: "",
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
          name: String.t(),
          collection: String.t(),
          table: String.t(),
          indexes: term,
          primary_keys: term,
          mappings: term,
          description: String.t()
        }

  @doc """
  Return the saved schema mapping struct
  """
  def saved_mapping(schema) do
    mapping_key(schema, @mapping) |> Store.get()
  end

  @doc """
  Returns the schema name for a schema mapping definition
  """
  def schema_name(schema) do
    mapping_key(schema, @name) |> Store.get()
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
  store the schema mapping as key value in the Schema store
    <namespace>.<collection>.name = <value>
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

    schema_name = if schema.name == "", do: "public", else: schema.name
    mapping_key(schema, @name) |> Store.set(schema_name)

    mapping_key(schema, @table) |> Store.set(schema.table)
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
