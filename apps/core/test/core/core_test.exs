defmodule MS.CoreTest do
  use ExUnit.Case, async: true
  alias MS.Core.Schema
  alias MS.Core.Schema.Mapping
  alias MS.Core.Schema.Store

  require Logger
  doctest MS.Core

  setup do
    {:ok, store} = Store.start_link()
    %{store: store}
  end

  test "greets the world" do
    assert MS.Core.hello() == :world
  end

  test "parse well-formed schema json" do
    fp = Path.absname("test/fixtures/schema.json")

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
    fp = Path.absname("test/fixtures/schema-malformed.json")

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
    case Schema.load_collection("users") do
      {:ok, schema} ->
        assert true, "users schema loaded"

        Logger.info("Loaded Schema: #{inspect(schema)}")
        Logger.info("Schema store pid #{inspect(schema_store)}")

        Schema.populate_schema_store(schema)

        assert Store.get("mosql.users.table") == "tbl_user"
        assert Store.get("mosql.users.name.column") == "full_name"
        assert Store.get("mosql.users.name.type") == "text"
        assert Store.get("mosql.users.full_name.type") == "text"
        assert Store.get("mosql.users.full_name.mongo_key") == "name"
        assert Store.get("mosql.users.id.primary_key") == true
        assert Store.get("mosql.users.full_name.primary_key") == false
        assert Store.get("mosql.users.columns") |> Enum.count() == 6

        Logger.info("Columns: #{inspect(Store.get("mosql.users.columns"))}")

      {:error, err} ->
        assert false, err
    end
  end

  test "test schema load nested keys", %{store: schema_store} do
    case Schema.load_collection("profiles") do
      {:ok, schema} ->
        assert true, "profiles schema loaded"

        Logger.info("Loaded Schema: #{inspect(schema)}")
        Logger.info("Schema store pid #{inspect(schema_store)}")

        Schema.populate_schema_store(schema)

        Logger.info("Columns: #{inspect(Schema.columns(schema))}")

        assert Store.get("mosql.profiles.comm_channel_phone.type") == "text"
        assert Store.get("mosql.profiles.comm_channel_phone.mongo_key") == "attributes.communicationChannels.phone"

      {:error, err} ->
        assert false, err
    end
  end
end
