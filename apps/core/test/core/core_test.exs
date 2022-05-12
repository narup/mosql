defmodule MS.CoreTest do
  use ExUnit.Case
  require Logger
  doctest MS.Core

  test "greets the world" do
    assert MS.Core.hello() == :world
  end

  test "parse schema json" do
    fp = Path.absname("test/fixtures/schema.json")
    with {:ok, raw_json} <- File.read(fp),
         {:ok, schema} <- Jason.decode(raw_json, [keys: :atoms]) do

          assert schema.collection == "users"
          assert schema.table == "user"

          first_field = hd(schema.fields)
          assert first_field.column == "id"

      Logger.info("Collection: #{inspect(schema.collection)}")
      Logger.info("Table: #{inspect(schema.table)}")
      Logger.info("First field column: #{inspect(first_field.column)}")
    else
      {:error, :enoent} ->
        IO.puts("Could not find schema.json")

      :error ->
        "something weird happened"
    end
  end
end
