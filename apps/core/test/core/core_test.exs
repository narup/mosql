defmodule MS.CoreTest do
  use ExUnit.Case, async: true
  alias MS.Core.Schema
  alias MS.Core.Schema.Field
  alias MS.Core.Schema.Store

  require Logger
  doctest MS.Core

  test "greets the world" do
    assert MS.Core.hello() == :world
  end

  test "parse well-formed schema json" do
    fp = Path.absname("test/fixtures/schema.json")

    with {:ok, raw_json} <- File.read(fp),
         fields <- Poison.Parser.parse!(raw_json, %{keys: :atoms!}) do
      schema = struct!(Schema, fields)
      Logger.info("Parsed schema: #{inspect(schema)}")

      assert schema.collection == "users"
      assert schema.table == "user"

      struct_fields = Enum.map(schema.fields, &struct!(Field, &1))
      schema = %Schema{schema | fields: struct_fields}

      Logger.info("Collection: #{inspect(schema.collection)}")
      Logger.info("Table: #{inspect(schema.table)}")
      Logger.info("Fields: #{inspect(schema.fields)}")
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

  test "test schema load" do
    case Schema.load_collection("users") do
      {:ok, schema} ->
        assert true, "users schema loaded"

        Logger.info("Loaded Schema: #{inspect(schema)}")

        Schema.populate_schema_store(schema)
        assert Store.get("users.table") == "tbl_user"
        assert Store.get("users.name.column") == "full_name"
        assert Store.get("users.name.type") == "text"

      {:error, err} ->
        assert false, err
    end
  end
end
