defmodule MosqlTest do
  use ExUnit.Case, async: true

  alias Mosql.Schema
  alias Mosql.Schema.Mapping
  alias Mosql.Store
  alias Mosql.SQL

  require Logger
  doctest Mosql

  setup do
    {:ok, store} = start_supervised(Store)
    Logger.info("mosql test PID #{inspect(store)}")
    %{store: store}
  end

  test "parse well-formed schema json" do
    fp = Path.absname("test/mosql/fixtures/schema.json")

    with {:ok, raw_json} <- File.read(fp),
         mappings <- Poison.Parser.parse!(raw_json, %{keys: :atoms!}) do
      schema = struct!(Schema, mappings)
      Logger.info("Parsed schema: #{inspect(schema)}")

      assert schema.collection == "users"
      assert schema.table == "user"

      struct_mappings = Enum.map(schema.mappings, &struct!(Mapping, &1))
      schema = %Schema{schema | mappings: struct_mappings}

      Logger.info("Collection: #{inspect(schema.collection)}")
      Logger.info("Table: #{inspect(schema.table)}")
      Logger.info("Mappings: #{inspect(schema.mappings)}")
    else
      {:error, :enoent} ->
        IO.puts("Could not find schema.json")

      :error ->
        "something weird happened"
    end
  end

  test "parse malformed schema json" do
    fp = Path.absname("test/mosql/fixtures/schema-malformed.json")

    try do
      with {:ok, raw_json} <- File.read(fp),
           _ <- Poison.Parser.parse!(raw_json, %{keys: :atoms!}) do
        assert false, "JSON parsing should fail with ParseError"
      else
        {:error, :enoent} ->
          assert false, "JSON parsing should fail with ParseError"

        :error ->
          assert false, "JSON parsing should fail with ParseError"
      end
    rescue
      Poison.ParseError ->
        Logger.info("Parser error happened as expected")
        assert true, "JSON parsing error"
    end
  end

  test "test schema load", %{store: schema_store} do
    case Schema.load_collection("users", "test/mosql/fixtures") do
      {:ok, schema} ->
        assert true, "users schema loaded"

        Logger.info("Loaded Schema: #{inspect(schema)}")
        Logger.info("Schema store pid #{inspect(schema_store)}")

        Schema.init_schema_store("mosql")
        Schema.populate_schema_store(schema)

        assert Store.get("mosql.users.table") == "tbl_user"
        assert Store.get("mosql.users.name.column") == "full_name"
        assert Store.get("mosql.users.name.type") == "text"
        assert Store.get("mosql.users.full_name.type") == "text"
        assert Store.get("mosql.users.full_name.mongo_key") == "name"
        assert Store.get("mosql.users.tbl_user.primary_key") == "id"
        assert Store.get("mosql.users.columns") |> Enum.count() == 6

        Logger.info("Columns: #{inspect(Store.get("mosql.users.columns"))}")

      {:error, err} ->
        assert false, err
    end
  end

  test "test schema load nested keys", %{store: schema_store} do
    case Schema.load_collection("profiles", "test/mosql/fixtures") do
      {:ok, schema} ->
        assert true, "profiles schema loaded"

        Logger.info("Loaded Schema: #{inspect(schema)}")
        Logger.info("Schema store pid #{inspect(schema_store)}")

        Schema.init_schema_store("mosql")
        Schema.populate_schema_store(schema)

        Logger.info("Columns: #{inspect(Schema.columns(schema))}")

        assert Store.get("mosql.profiles.comm_channel_phone.type") == "text"

        assert Store.get("mosql.profiles.comm_channel_phone.mongo_key") ==
                 "attributes.communicationChannels.phone"

      {:error, err} ->
        assert false, err
    end
  end

  test "test sql type values", %{store: schema_store} do
    case Schema.load_collection("types", "test/mosql/fixtures") do
      {:ok, schema} ->
        assert true, "types schema loaded"

        Logger.info("Loaded Schema: #{inspect(schema)}")
        Logger.info("Schema store pid #{inspect(schema_store)}")

        Schema.init_schema_store("mosql")
        Schema.populate_schema_store(schema)

        Logger.info("Columns: #{inspect(Schema.columns(schema))}")

        values_doc = %{
          "_id" => "6277f677b99d8078d17d5918",
          "typeVarchar" => "JohnLongFirstName DoelongLastName",
          "typeBoolean" => true,
          "typeSmallInt" => 99999,
          "typeInteger" => 999_999,
          "typeBigInt" => 99_999_999_999,
          "typeNumeric" => 40.24,
          "created_date" => "2022-11-21 12:12:47.895-05"
        }

        row_values = SQL.to_insert_values(schema, values_doc)
        IO.puts("Row values: #{inspect(row_values)}")

        assert row_values == [
                 "'6277f677b99d8078d17d5918'",
                 "'JohnLongFirstName DoelongLastName'",
                 "'true'",
                 "99999",
                 "999999",
                 "99999999999",
                 "40.24",
                 "'2022-11-21 12:12:47.895-05'"
               ]

      {:error, err} ->
        assert false, err
    end
  end
end
