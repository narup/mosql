defmodule MS.SQL do
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
