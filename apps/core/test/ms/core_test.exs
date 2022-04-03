defmodule MS.CoreTest do
  use ExUnit.Case
  doctest MS.Core

  test "greets the world" do
    assert MS.Core.hello() == :world
  end
end
