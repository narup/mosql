defmodule MS.SchemaStoreTest do
  use ExUnit.Case, async: true

  alias MS.Core.Schema.Store

  test "stores values by key" do
    assert Store.set("users.table", "user_table") == :ok
    assert Store.get("users.table") == "user_table"
  end
end
