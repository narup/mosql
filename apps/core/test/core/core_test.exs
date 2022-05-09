defmodule MS.CoreTest do
  use ExUnit.Case
  doctest MS.Core

  test "greets the world" do
    assert MS.Core.hello() == :world
  end

  test "parse schema json" do
    with {:ok, raw_json} <- File.read("fixtures/schema.json"),
         {:ok, schema} <- Jason.decode(raw_json, [:atoms]) do
      assert schema.collection == "users"
    end
  end
end
