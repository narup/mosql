defmodule MosqlCLI do

  use Bakeware.Script

  @moduledoc """
  Documentation for `MosqlCLI`.
  """

  @impl Bakeware.Script
  def main(_args) do
    IO.puts("MosqlCLI....")
    Application.ensure_loaded(:mosql_cli)
    mongo_opts = Application.fetch_env!(:mosql_cli, :mongo_opts)
    IO.puts(mongo_opts)
  end
end
