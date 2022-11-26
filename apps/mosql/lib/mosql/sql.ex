defmodule MS.SQL do
  require Logger

  alias MS.Schema
  alias MS.Postgres

  @alter_add_column "add_column"
  @alter_drop_column "drop_column"
  @alter_data_type "data_type"
  @alter_add_not_null "add_not_null"

  @doc """
  Prepare the SQL DB for export
  1. Create tables, if not exists
  2. Alter tables, if schema changed
  3. Delete data from tables
  """
  def prepare(export) do
    try do
      create_tables(export.schemas)
    rescue
      e in RuntimeError ->
        {:error, e.message}

      e in Postgrex.Error ->
        Logger.error("error preparing export db. error: #{inspect(e)}")
        {:error, e.postgres.message}
    end
  end

  defp create_tables(schemas) do
    Enum.each(schemas, &create_table(&1))
  end

  defp create_table(schema) do
    Logger.info("Creating table #{schema.table}")
    create_table_with_columns_sql(schema) |> Postgres.query!()
    Logger.info("Created table #{schema.table}")
  end

  # Creates a current table definition map for each column
  # and column attribtues for an easier lookup
  # Format:
  # [
  #   %{ column_name_1 => %{column attributes map...} },
  #   %{ column_name_2 => %{colum attributes map...} }
  #   ...
  # ]
  def table_definition(db, table) do
    table_definition_sql(db, table)
    |> Postgres.query!()
    |> create_table_definition_map()
  end

  defp create_table_definition_map(res) do
    Enum.map(res.rows, &table_definition_map(&1, res.columns))
  end

  defp table_definition_map(row_values, columns) do
    row_map =
      row_values
      |> Enum.with_index()
      |> Enum.reduce(%{}, &table_definition_column_map(columns, &1, &2))

    %{row_map.column_name => row_map}
  end

  defp table_definition_column_map(columns, {elem, index}, acc) do
    key = Enum.at(columns, index) |> String.to_atom()
    Map.put(acc, key, elem)
  end

  defp table_definition_sql(db, table) do
    ~s(
      SELECT
              table_schema
             ,table_name
             ,column_name
             ,ordinal_position
             ,is_nullable
             ,data_type
             ,character_maximum_length
             ,numeric_precision
             ,numeric_precision_radix
             ,numeric_scale
             ,datetime_precision
      FROM
            information_schema.columns
      WHERE table_catalog = '#{db}' and table_name = '#{table}'
    )
  end

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
  def create_table_with_columns_sql(schema) do
    schema_name = Schema.schema_name(schema)
    Logger.info("Generating table creation SQL for #{schema_name}.#{schema.collection}")

    columns =
      schema
      |> Schema.columns()
      |> Enum.map(&column_definition(schema, &1))
      |> Enum.join("\n\t,")

    ~s(
      CREATE TABLE IF NOT EXISTS #{schema_name}.#{table_name(schema)} (
         #{columns}
      \);
    )
  end

  @doc """
    Generates a SQL string for creating a table if not exists
  """
  def create_table_if_not_exists_sql(schema) do
    schema_name = Schema.schema_name(schema)
    table_name = table_name(schema)
    "CREATE TABLE IF NOT EXISTS #{schema_name}.#{table_name}"
  end

  @doc """
    Generates a SQL string for checking if a table exists in the schema
  """
  def table_exists_sql(schema) do
    schema_name = Schema.schema_name(schema)
    table_name = table_name(schema)
    ~s(
        SELECT EXISTS (
          SELECT table_name FROM information_schema.tables
          WHERE table_schema = '#{schema_name}' AND table_name = '#{table_name}'
        \)
      )
  end

  @doc """
  SQL for drop table
  """
  def drop_table_sql(schema) do
    schema_name = Schema.schema_name(schema)
    table_name = table_name(schema)
    "DROP TABLE IF EXISTS #{schema_name}.#{table_name}"
  end

  @doc """
  SQL for truncate table
  """
  def truncate_table_sql(schema) do
    "TRUNCATE TABLE #{table_name(schema)}"
  end

  @doc """
  SQL for adding a new column if it does not exists
  """
  def create_column_if_not_exists_sql(schema, column) do
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
  def upsert_document_sql(schema, mongo_document \\ %{}) do
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
