defmodule MS.Schema do
  alias __MODULE__
  alias MS.Schema.Mapping
  alias MS.Store

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
  @derive [Poison.Encoder]
  defstruct ns: "", collection: "", table: "", indexes: [], primary_keys: [], mappings: []

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

defmodule MS.Schema.SQL do
  require Logger

  alias MS.Schema

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
  def create_table_with_columns(schema) do
    Logger.info("Generating table creation SQL for #{schema.ns}.#{schema.collection}")

    columns =
      schema
      |> Schema.columns()
      |> Enum.map(&column_definition(schema, &1))
      |> Enum.join("\n\t,")

    ~s(
      CREATE TABLE IF NOT EXISTS #{schema.ns}.#{table_name(schema)} (
         #{columns}
      \);
    )
  end

  @doc """
    Generates a SQL string for creating a table if not exists
  """
  def create_table_if_not_exists(schema) do
    table_name = table_name(schema)
    "CREATE TABLE IF NOT EXISTS #{schema.ns}.#{table_name}"
  end

  @doc """
    Generates a SQL string for checking if a table exists in the schema
  """
  def table_exists(schema) do
    table_name = table_name(schema)
    ~s(
        SELECT EXISTS (
          SELECT table_name FROM information_schema.tables
          WHERE table_schema = '#{schema.ns}' AND table_name = '#{table_name}'
        \)
      )
  end

  @doc """
  SQL for drop table
  """
  def drop_table(schema) do
    "DROP TABLE IF EXISTS #{table_name(schema)}"
  end

  @doc """
  SQL for truncate table
  """
  def truncate_table(schema) do
    "TRUNCATE TABLE #{table_name(schema)}"
  end

  @doc """
  SQL for adding a new column if it does not exists
  """
  def create_column_if_not_exists(schema, column) do
    table_name = table_name(schema)
    ~s(
        ALTER TABLE #{schema.ns}.#{table_name} ADD COLUMN
        IF NOT EXISTS #{column_definition(schema, column)}
    )
  end

  @doc """
  Generates upsert SQL statement for a given schema and a mongo document
   INSERT INTO <table_name> (column1, column2...)
    VALUES (value1, value2...)
    ON CONFLICT (primary_key_field) DO UPDATE SET column = EXCLUDED.column...;
  """
  def upsert_document(schema, mongo_document \\ %{}) do
    table_name = table_name(schema)
    primary_key = Schema.primary_key(schema)

    column_list = schema |> Schema.columns()

    columns = Enum.join(column_list, "\n\t,")

    update_columns =
      column_list
      |> Enum.filter(&(!Schema.is_primary_key?(schema, &1)))
      |> Enum.map(&"#{&1} = EXCLUDED.#{&1}")
      |> Enum.join(", ")

    values = column_values(schema, column_list, mongo_document)

    ~s(
      INSERT INTO #{schema.ns}.#{table_name} (
         #{columns}
      \) VALUES (
        #{values}
      \) ON CONFLICT ( #{primary_key} \) DO UPDATE SET #{update_columns};
    )
  end

  @type_map %{
    "string" => "text",
    "boolean" => "boolean",
    "integer" => "integer",
    "float" => "numeric",
    "datetime" => "timestamp with time zone"
  }

  def mongo_to_sql_type(mongo_type) do
    Map.get(@type_map, mongo_type)
  end

  defp column_definition(schema, column) do
    type = Schema.type(schema, column) |> String.upcase()

    if Schema.is_primary_key?(schema, column) do
      "#{column} #{type} PRIMARY KEY"
    else
      "#{column} #{type}"
    end
  end

  defp column_values(schema, columns, mongo_document) do
    Enum.map(columns, &column_value(schema, &1, mongo_document)) |> Enum.join(", ")
  end

  defp column_value(schema, column, mongo_document) do
    mongo_key = Schema.mongo_key(schema, column)
    "'#{Map.get(mongo_document, mongo_key)}'"
  end

  defp table_name(schema) do
    Schema.table_name(schema)
  end
end
