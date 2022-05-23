defmodule MS.Core.Schema do
  alias __MODULE__
  alias MS.Core.Schema.Field
  alias MS.Core.Schema.Store

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

  def load_collection(collection) do
    schema_file_path =
      @schema_files_path
      |> Path.join("#{collection}.json")
      |> Path.absname()

    Logger.info("Schema file path for collection '#{collection}' is '#{schema_file_path}'")

    try do
      with {:ok, raw_json} <- File.read(schema_file_path),
           fields <- Poison.Parser.parse!(raw_json, %{keys: :atoms!}) do
        schema = struct!(Schema, fields)

        Logger.info(
          "Parsed schema for collection '#{collection}' from file path '#{schema_file_path}'"
        )

        struct_fields = Enum.map(schema.fields, &Field.to_struct(&1))
        schema = %{schema | fields: struct_fields}
        {:ok, schema}
      else
        {:error, :enoent} ->
          {:error, "Schema file not found for collection '#{collection}'"}
      end
    rescue
      Poison.ParseError ->
        {:error, "JSON parsing failed for collection '#{collection}"}
    end
  end

  @doc """
  store the schema mapping as key value in the Schema store
    <collection>.table = <value>
    <collection>.<field>.indexes = []
    <collection>.<field>.column = <value>
    <collection>.<field>.type = <value>
  """
  def populate_schema_store(schema) do
    Store.set("#{schema.collection}.table", "#{schema.table}")
    store_fields(schema)
  end

  defp store_fields(schema) do
    Enum.each(schema.fields, &store_field_mappings(schema.collection, &1))
  end

  defp store_field_mappings(collection, field) do
    field_key(collection, field, "column") |> Store.set(field.column)
    field_key(collection, field, "type") |> Store.set(field.type)
  end

  defp field_key(collection, field, key) do
    "#{collection}.#{field.field}.#{key}"
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

  def to_struct(values) do
    struct!(Field, values)
  end
end
