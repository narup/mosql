defmodule DbTest do
  use ExUnit.Case
  alias MS.BroadwayMongo
  doctest BroadwayMongo

  test "greets the world" do
    assert BroadwayMongo.hello() == :world
  end
end
