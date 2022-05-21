defmodule MS.Core.Schema do
  alias __MODULE__
  alias MS.Core.Schema.Field

  require Logger

  @moduledoc """
  Represents the schema mapping between MongoDB collection and Postgres tabl
  """
  defstruct collection: "", table: "", indexes: [], fields: []

  @schema_files_path Application.fetch_env!(:core, :schema_files_path)

  @typedoc """
  Schema type definition
  """
  @type t :: %__MODULE__{
          collection: String.t(),
          table: String.t(),
          indexes: term,
          fields: term
        }

  def load_schema_mappings(collection) do
    schema_file_path =
      @schema_files_path
      |> Path.join("#{collection}.json")
      |> Path.absname()

    Logger.info("Schema file path for collection '#{collection}' is '#{schema_file_path}'")

    try do
      with {:ok, raw_json} <- File.read(schema_file_path),
           fields <- Poison.Parser.parse!(raw_json, %{keys: :atoms!}) do
        schema = struct!(Schema, fields)
        Logger.info("Parsed schema for collection '#{collection}' from file path '#{schema_file_path}'")

        struct_fields = Enum.map(schema.fields, &struct!(Field, &1))
        schema = %{schema | fields: struct_fields}

        IO.inspect(schema)
      else
        {:error, :enoent} ->
          "JSON parsing should fail with ParseError"

        :error ->
          "JSON parsing should fail with ParseError"
      end
    rescue
      Poison.ParseError ->
        Logger.info("Parser error happened as expected")
    end
  end
end

defmodule MS.Core.Schema.Field do
  alias __MODULE__

  @moduledoc """
  Represents the field
  """
  defstruct field: "", column: "", type: ""

  @typedoc """
  Field type definition
  """
  @type t :: %__MODULE__{
          field: String.t(),
          column: String.t(),
          type: String.t()
        }
end

# <collection>.<field>.table = <value>
# <collection>.<field>.indexes = []
# <collection>.<field>.column = <value>
# <collection>.<field>.type = <value>
