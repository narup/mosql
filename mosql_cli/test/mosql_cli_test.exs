defmodule MosqlCliTest do
  use ExUnit.Case
  doctest MosqlCli

  test "greets the world" do
    assert MosqlCli.hello() == :world
  end
end
