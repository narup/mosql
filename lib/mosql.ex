defmodule Mosql do
  @moduledoc """
  Specification for `Mosql`. It is used to export data from MongoDB
  database to Postgres database

  There are two kind of Mosql exports: full export and change stream

  ## FullExport

  FullExport is used to do a one time full export of MongoDB database
  to a destination Postgres database using the schema mapping definitions
  that maps each collection and document fields to SQL table and table
  attributes. The process to start the export:

    1. Create a postgres export type with a namespace. Namespace has to be unique

      Mosql.create_postgres_export("my_namespace")

    The export can be customized by using the `options` argument to provide `exclusions` and `exclusives`
       * `:exclusions` - the list of collections to exclude from the export
       * `:exclusives` - the list of collections that must be included

    2. Generate export schema definitions and export to a file system

      ex = Mosql.generate_default_schemas(export, [persist: true, export_path: "schema"])
      Export.to_json(ex, "schema")

    3. Reload the (updated) schema files from the path to the export

      Mosql.reload_schema_files(export, schema_path)

    3. Trigger full export

      Mosql.start_full_export(export)
  """

  alias Mosql.FullExport
  alias Mosql.Export
  alias Mosql.Schema
  alias Mosql.SQL
  alias Mosql.Postgres
  alias Mosql.Mongo

  require Logger

  @type_postgres "postgres"

  @doc """
  Perform one time setup operation for Mosql to initialize Mosql's internal
  database and other things. Internal DB is based on `Erlang Mnesia` Database
  and used by Mosql to store exports and schema definition.
  """
  def setup() do
    Mosql.Export.setup!()
  end

  @doc """
  Starts the mongo process. This has to be executed before performing any MongoDB
  operations such as `generate_default_schemas`
  """
  def start_mongo(mongo_opts \\ []) do
    start_mongo_with_opts(mongo_opts)
  end

  defp start_mongo_with_opts(mongo_opts) when length(mongo_opts) > 0 do
    mongo_opts |> Mongo.child_spec() |> start_process()
  end

  defp start_mongo_with_opts([]) do
    Logger.info("Starting mongo with application configuration")

    Application.get_env(:mosql, :mongo_opts)
    |> Mongo.child_spec()
    |> start_process()
  end

  @doc """
  Starts the postgres process
  """
  def start_postgres(postgres_opts \\ []) do
    start_postgres_with_opts(postgres_opts)
  end

  defp start_postgres_with_opts(postgres_opts) when length(postgres_opts) > 0 do
    postgres_opts |> Postgres.child_spec() |> start_process()
  end

  defp start_postgres_with_opts([]) do
    Logger.info("Starting postgres with application configuration")

    Application.get_env(:mosql, :postgres_opts)
    |> Postgres.child_spec()
    |> start_process()
  end

  @doc """
  Starts the full export process that handles the full data export. This starts a `Broadway`
  producer and processors that performs the export
  """
  def start_full_export_process(opts) do
    start_process(Mosql.Store, [])
    start_process(Mosql.FullExport, opts)
  end

  @doc """
  Starts a Mongo changestream based data export process. This starts a `Broadway` process that
  includes a producer that listens to Mongo change stream and the processors that handles the
  data export
  """
  def start_change_stream_process(opts) do
    start_process(Mosql.Store, [])
    start_process(Mosql.ChangeStreamExport, opts)
  end

  @doc """
  Starts the Mosql server process. For individual processes see - `start_mongo/1`, `start_postgres/1`,
  `start_full_export_process/1`, and `start_change_stream_process/1`
  """
  def start(opts \\ [mongo_opts: [], postgres_opts: [], full_export_opts: []]) do
    start_mongo(opts[:mongo_opts])
    start_postgres(opts[:postgres_opts])
    start_full_export_process(opts[:full_export_opts])
  end

  defp start_process(child_spec) when is_map(child_spec) do
    pid =
      case Supervisor.start_child(Mosql.ExportSupervisor, child_spec) do
        {:ok, pid} -> pid
        {:error, {:already_started, pid}} -> pid
      end

    Logger.info("Child process started with pid #{inspect(pid)} and spec #{inspect(child_spec)}")
    pid
  end

  defp start_process(module, opts) do
    pid =
      case Supervisor.start_child(Mosql.ExportSupervisor, {module, opts}) do
        {:ok, pid} -> pid
        {:error, {:already_started, pid}} -> pid
      end

    Logger.info("#{inspect(module)} process started with pid #{inspect(pid)}")

    pid
  end

  @doc """
  creates the complete postgres type export definition for the given namespace
  """
  def create_postgres_export(namespace, options \\ []) do
    Export.new(namespace, @type_postgres, options)
  end

  @doc """
  Fetch the postgres export based on the namespace and the type
  """
  def fetch_postgres_export(namespace) do
    Export.fetch(namespace, @type_postgres)
  end

  @doc """
  Loads the saved export to the schema store for the export
  """
  def load_postgres_export(namespace) do
    case Export.fetch(namespace, @type_postgres) do
      {:ok, ex} ->
        if Enum.count(ex.schemas) > 0 do
          Export.populate_schema_store(ex)
          {:ok, ex}
        else
          {:error, "Missing schema definitions"}
        end

      {:error, :not_found} ->
        {:error, :not_found}

      _ ->
        IO.puts("Something unexpected happened, please try again.")
    end
  end

  @doc """
  Removes the saved export based on the namespace and type
  """
  def remove_export(namespace, type) do
    Export.delete(namespace, type)
  end

  @doc """
  Generates the default export schema definitions for the given export.
  These schema definitions can be modified to customize the export at the
  collection and field level. It takes additional opts to provide `export_path`
  and `persist`
       * `:export_path` - export the schema as JSON files on the given export path
       * `:persist` - persist export definition in the MoSQL internal store

  MoSQL internal store is a mnesia based disk store. See `Mosql.Export.setup!()` for
  more details
  """
  def generate_default_schemas(export, opts \\ []) do
    schemas = Export.generate_schema_mappings(export)
    ex = %{export | schemas: schemas}

    if Keyword.has_key?(opts, :export_path) do
      Export.to_json(ex, Keyword.get(opts, :export_path))
    end

    if Keyword.has_key?(opts, :persist) do
      Export.save(ex)
    end
  end

  @doc """
  Reload the schema definition from the JSON files to the given export from
  the file path. This will override the existing in-memory schema definition
  associated with the export
  """
  def reload_schema_files(export, schema_path) do
    Logger.info("Loading schema files from the path #{schema_path}....")
    schemas = Schema.load_schema_files(export.ns, schema_path)

    # if any schema failed to load return the error
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
    case Enum.count(export.schemas) do
      0 ->
        {:error, "Missing schema definitions"}

      _ ->
        Export.populate_schema_store(export)
        SQL.prepare(export)
        FullExport.trigger(export.ns)

        {:ok, "Full export pipeline started...."}
    end
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
  defp schema_load_error({:ok, _}), do: false

  defp no_error_schema({:ok, _}), do: true
  defp no_error_schema({:error, _}), do: false
end
