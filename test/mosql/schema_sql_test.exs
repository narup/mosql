defmodule SchemaSQLTest do
  use ExUnit.Case, async: true

  alias Mosql.Store
  alias Mosql.SQL

  require Logger

  setup do
    {:ok, store} = start_supervised(Store)
    Logger.info("schema test PID #{inspect(store)}")
    %{store: store}

    Store.set("mosql.users.name", "schema_users")
    Store.set("mosql.users.table", "tbl_user")
    Store.set("mosql.users.primary_keys", ["id"])
    Store.set("mosql.users.tbl_user.primary_key", "id")

    Store.set("mosql.users._id.column", "id")
    Store.set("mosql.users.id.type", "text")
    Store.set("mosql.users.id.mongo_key", "_id")
    Store.set("mosql.users.id.primary_key", true)

    Store.set("mosql.users.name.column", "full_name")
    Store.set("mosql.users.name.type", "text")
    Store.set("mosql.users.full_name.type", "text")
    Store.set("mosql.users.full_name.mongo_key", "name")

    Store.set("mosql.users.email.column", "email")
    Store.set("mosql.users.email.type", "text")
    Store.set("mosql.users.email.mongo_key", "email")

    Store.set("mosql.users.zip.column", "zip_code")
    Store.set("mosql.users.zip.type", "text")
    Store.set("mosql.users.zip_code.type", "varchar(50)")
    Store.set("mosql.users.zip_code.mongo_key", "zip")

    Store.set("mosql.users.created_date.column", "created_date")
    Store.set("mosql.users.created_date.type", "timestamp with time zone")
    Store.set("mosql.users.created_date.mongo_key", "created_date")

    Store.set("mosql.users.columns", [
      "id",
      "full_name",
      "email",
      "zip_code",
      "created_date"
    ])

    schema = %{ns: "mosql", collection: "users", table: "tbl_user"}
    %{store: store, schema: schema}
  end

  test "stores values by key" do
    assert Store.set("users.table", "user_table") == :ok
    assert Store.get("users.table") == "user_table"
  end

  @user_flat_document %{
    "_id" => "6277f677b99d8078d17d5918",
    "name" => "John Doe",
    "email" => "john.doe@johndoe.com",
    "zip" => "94117",
    "city" => "San Francisco",
    "created_date" => "523523525"
  }

  test "test SQL queries", %{store: store, schema: schema} do
    Logger.info("Schema store pid #{inspect(store)}")

    create_all_sql = SQL.create_table_with_columns_sql(schema)
    Logger.info("Create table with columns SQL:\n #{create_all_sql}")

    create_sql = SQL.create_table_if_not_exists_sql(schema)
    Logger.info("Create table if not exists SQL:\n #{create_sql}")

    table_exists_sql = SQL.table_exists_sql(schema)
    Logger.info("Check if table exists SQL:\n #{table_exists_sql}")

    column_sql = SQL.add_column_if_not_exists_sql(schema, "full_name")
    Logger.info("Add column SQL:\n #{column_sql}")

    upsert_sql = SQL.upsert_document_sql(schema, @user_flat_document)
    Logger.info("Upsert data SQL:\n #{upsert_sql}")
  end

  test "test new columns on the schema mapping" do
    schema_columns = Store.get("mosql.users.columns")

    existing_columns = %{
      "id" => "1",
      "full_name" => "1",
      "email" => "1",
      "created_date" => "1"
    }

    assert ["zip_code"] = SQL.filter_new_columns(schema_columns, existing_columns)
  end

  test "test columns removed from the schema mapping" do
    schema_columns = [
      "id",
      "full_name",
      "created_date"
    ]

    existing_columns = %{
      "id" => "1",
      "full_name" => "1",
      "email" => "1",
      "zip_code" => "1",
      "created_date" => "1"
    }

    assert ["email", "zip_code"] = SQL.filter_missing_columns(schema_columns, existing_columns)
  end

  test "column values", %{schema: schema} do
    empty_values = SQL.to_insert_values(schema, %{})
    assert empty_values == ["''", "''", "''", "''", "''"]

    doc_1 = %{
      "_id" => "6277f677b99d8078d17d5918",
      "name" => "John Doe",
      "email" => "john.doe@johndoe.com",
      "zip" => "94117",
      "created_date" => "523523525"
    }

    values_1 = SQL.to_insert_values(schema, doc_1)

    assert values_1 == [
             "'6277f677b99d8078d17d5918'",
             "'John Doe'",
             "'john.doe@johndoe.com'",
             "'94117'",
             "'523523525'"
           ]
  end
end
