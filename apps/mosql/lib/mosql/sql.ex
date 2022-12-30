defmodule MS.SQL do
  require Logger

  alias MS.Schema
  alias MS.Postgres
  alias MS.Export

  @doc """
  Prepare the SQL DB for the full export. It performs the following 3 steps:
      1. Truncate data from tables if exists
      2. Create new tables, if not exists
      3. Alter existing tables, if schema changed
  """
  def prepare(export) do
    try do
      truncate_tables(export)
      create_tables(export)
      alter_tables(export)
    rescue
      e in RuntimeError ->
        {:error, e.message}

      e in Postgrex.Error ->
        Logger.error("error preparing export db. error: #{inspect(e)}")
        {:error, e.postgres.message}
    end
  end

  defp truncate_tables(export) do
    Enum.each(export.schemas, &truncate_table(&1))
  end

  defp truncate_table(schema) do
    if table_exists(schema) do
      Logger.info("truncating table #{full_table_name(schema)}")
      truncate_table_sql(schema) |> Postgres.query!()
      Logger.info("table #{full_table_name(schema)} truncated")
    end
  end

  defp create_tables(export) do
    Enum.each(export.schemas, &create_table(&1))
  end

  defp create_table(schema) do
    Logger.info("creating table #{full_table_name(schema)}")
    create_table_with_columns_sql(schema) |> Postgres.query!()
    Logger.info("created table #{full_table_name(schema)}")
  end

  def alter_tables(export) do
    db_name = Export.destination_db_name(export)
    Enum.each(export.schemas, &alter_table(&1, db_name))
  end

  # Alter existing table based on the change in schema definition
  # Supported changeset includes:
  #       "add_column"
  #       "drop_column"
  #       "data_type"
  #       "add_not_null"
  def alter_table(schema, db_name) do
    table_name = Schema.table_name(schema)

    schema_columns = Schema.columns(schema)
    existing_columns = table_columns(db_name, table_name)

    cond do
      Enum.count(schema_columns) > Enum.count(existing_columns) ->
        Logger.info(
          "Found new columns in the updated schema definition for table #{full_table_name(schema)}"
        )

        schema_columns
        |> filter_new_columns(existing_columns)
        |> Enum.each(&add_column(schema, &1))

      Enum.count(schema_columns) < Enum.count(existing_columns) ->
        Logger.info(
          "Found less columns in the updated schema definition for table #{full_table_name(schema)}"
        )

        schema_columns
        |> filter_missing_columns(existing_columns)
        |> Enum.each(&remove_column(schema, &1))

      true ->
        IO.puts("Schema unchanged")
    end
  end

  def table_exists(schema) do
    res = table_exists_sql(schema) |> Postgres.query!()
    Enum.empty?(res.rows) == false
  end

  # Filters the additional column in the new schema definition
  def filter_new_columns(schema_columns, existing_columns) do
    Enum.filter(schema_columns, &(Map.has_key?(existing_columns, &1) == false))
  end

  defp add_column(schema, column) do
    Logger.info("Adding new column #{column} in table #{full_table_name(schema)}")
    add_column_if_not_exists_sql(schema, column) |> Postgres.query!()
    Logger.info("Added new column #{column} in table #{full_table_name(schema)}")
  end

  # Filters the missing column in the new schema definition
  def filter_missing_columns(schema_columns, existing_columns) do
    Map.keys(existing_columns) |> Enum.filter(&(Enum.member?(schema_columns, &1) == false))
  end

  defp remove_column(schema, column) do
    Logger.info(
      "Removing column no longer found in the schema definition #{column} for table #{full_table_name(schema)}"
    )

    remove_column_if_exists_sql(schema, column) |> Postgres.query!()
    Logger.info("Removed column #{column} from the table #{full_table_name(schema)}")
  end

  # Creates a current table definition map for each column
  # and column attribtues for an easier lookup
  # Format:
  #   %{
  #       column_name_1 => %{column attributes map...},
  #       column_name_2 => %{colum attributes map...
  #       ...
  #    },
  # If table does not exists returns empty map %{}
  def table_columns(db, table) do
    table_definition_sql(db, table)
    |> Postgres.query!()
    |> create_table_definition_map()
  end

  defp create_table_definition_map(res) do
    case res.rows do
      [] -> %{}
      _ -> Enum.map(res.rows, &table_definition_map(&1, res.columns)) |> Enum.reduce(&Map.merge/2)
    end
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
    table_name = full_table_name(schema)
    Logger.info("Generating table creation SQL for #{table_name}")

    columns =
      schema
      |> Schema.columns()
      |> Enum.map(&column_definition(schema, &1))
      |> Enum.join(", ")

    ~s(
      CREATE TABLE IF NOT EXISTS #{table_name} (
        #{columns}
      \);
    )
  end

  @doc """
    Generates a SQL string for creating a table if not exists
  """
  def create_table_if_not_exists_sql(schema) do
    table_name = full_table_name(schema)
    "CREATE TABLE IF NOT EXISTS #{table_name}"
  end

  @doc """
    Generates a SQL string for checking if a table exists in the schema
  """
  def table_exists_sql(schema) do
    schema_name = Schema.schema_name(schema)
    table_name = Schema.table_name(schema)
    ~s(
      SELECT table_name FROM information_schema.tables
          WHERE table_schema = '#{schema_name}' AND table_name = '#{table_name}'
      )
  end

  @doc """
  SQL for drop table
  """
  def drop_table_sql(schema) do
    table_name = full_table_name(schema)
    "DROP TABLE IF EXISTS #{table_name}"
  end

  @doc """
  SQL for truncate table
  """
  def truncate_table_sql(schema) do
    table_name = full_table_name(schema)
    "TRUNCATE TABLE #{table_name}"
  end

  @doc """
  SQL for adding a new column if it does not exists
  """
  def add_column_if_not_exists_sql(schema, column) do
    table_name = full_table_name(schema)
    ~s(
        ALTER TABLE #{table_name} ADD COLUMN
        IF NOT EXISTS #{column}
    )
  end

  @doc """
  SQL for removing a column if it does exists
  """
  def remove_column_if_exists_sql(schema, column) do
    table_name = full_table_name(schema)
    ~s(
        ALTER TABLE #{table_name} DROP COLUMN
        IF EXISTS #{column_definition(schema, column)}
    )
  end

  @doc """
  Generates upsert SQL statement for a given schema and a mongo document
   INSERT INTO <table_name> (column1, column2...)
    VALUES (value1, value2...)
    ON CONFLICT (primary_key_field) DO UPDATE SET column = EXCLUDED.column...;
  """
  def upsert_document_sql(schema, mongo_document \\ %{}) do
    table_name = full_table_name(schema)
    primary_key = Schema.primary_key(schema)

    column_list = schema |> Schema.columns()

    columns = Enum.join(column_list, ", ")

    update_columns =
      column_list
      |> Enum.filter(&(!Schema.is_primary_key?(schema, &1)))
      |> Enum.map(&"#{&1} = EXCLUDED.#{&1}")
      |> Enum.join(", ")

    values = column_values(schema, column_list, mongo_document)

    ~s(
      INSERT INTO #{table_name} ( #{columns} \)
      VALUES ( #{values} \)
      ON CONFLICT ( #{primary_key} \)
      DO UPDATE SET #{update_columns}
    )
  end

  # small_integer -> -32768 to +32767
  # integer -> -2147483648 to +2147483647
  # big_integer -> -9223372036854775808 to 9223372036854775807
  @type_map %{
    "string" => "text",
    "boolean" => "boolean",
    "small_integer" => "smallint",
    "integer" => "integer",
    "big_integer" => "bigint",
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

  defp full_table_name(schema) do
    schema_name = Schema.schema_name(schema)
    table_name = Schema.table_name(schema)
    "#{schema_name}.#{table_name}"
  end
end
