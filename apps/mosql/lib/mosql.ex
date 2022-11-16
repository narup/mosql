defmodule MS.MoSQL do
  @moduledoc """
  Specification for `MS.MoSQL`. It is used to export data from MongoDB
  database to Postgres database

  There are two kind of MoSQL exports: full export and change stream

  ## FullExport

  FullExport is used to do a one time full export of MongoDB database
  to a destination Postgres database using the schema mapping definitions
  that maps each collection and document fields to SQL table and table
  attributes. The process to start the export:

    1. Create a postgres export type with a namespace. Namespace has to be unique

      MS.MoSQL.create_postgres_export("my_namespace")

      The export can be customized by using the `options` argument
      to provide `exclusions` and `exclusives`
       * `:exclusions` - the list of collections to exclude from the export
       * `:exclusives` - the list of collections that must be included

    2. Generate export schema definition files
      MS.MoSQL.generate_schema_files(export, schema_path)

    3. Trigger full export
      MS.MoSQL.start_full_export(export)
  """

  alias MS.Pipeline.FullExport
  alias MS.Export
  alias MS.Schema

  require Logger

  @type_postgres "postgres"

  @doc """
  creates the complete postgres type export definition for the given namespace
  """
  def create_postgres_export(namespace, options \\ []) do
    Export.new(namespace, @type_postgres, options)
  end

  @doc """
  Generate the given export schemas with JSON schema definition files in a given
  path. These schema definitions can be modified to customize the export at the
  collection and field level
  """
  def generate_schema_files(export, schema_path) do
    schemas = Export.generate_schema_mappings(export)

    export = %{export | schemas: schemas}
    Export.to_json(export, schema_path)
  end

  @doc """
  Reload the schema definition from the JSON files to the given export from
  the file path. This will override the existing in-memory schema definition
  associated with the export
  """
  def reload_schema_files(export, schema_path) do
    Logger.info("Loading schema files from the path #{schema_path}....")
    schemas = Schema.load_schema_files(export.ns, schema_path)

    if has_schema_load_errors(schemas) do
      {:error, schema_load_errors(schemas)}
    else
      {:ok, %{export | schemas: loaded_schemas(schemas)}}
    end
  end

  @doc """
  Start the full export process for the given export
  """
  def start_full_export(export) do
    Export.populate_schema_store(export)
    FullExport.trigger()
  end

  defp has_schema_load_errors(schemas) do
    Enum.any?(schemas, &schema_load_error(&1))
  end

  defp schema_load_errors(schemas) do
    Enum.filter(schemas, &schema_load_error(&1))
  end

  defp loaded_schemas(schemas) do
    Enum.filter(schemas, &no_error_schema(&1)) |> Enum.map(fn {:ok, schema} -> schema end)
  end

  defp schema_load_error({:error, _}), do: true

  defp no_error_schema({:ok, _}), do: true
  defp no_error_schema({:error, _}), do: false
end
