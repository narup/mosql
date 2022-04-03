defmodule DbTest do
  use ExUnit.Case
  doctest BroadwayMongo

  test "greets the world" do
    assert BroadwayMongo.hello() == :world
  end
end
