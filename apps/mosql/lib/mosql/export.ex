defmodule MS.Export do
  alias __MODULE__

  alias MS.Schema
  alias MS.SQL
  alias MS.Mongo

  require Logger
  require Memento

  @moduledoc """
  Represents the export definition and other configurations of the export
  `ns` namespace has to be unique across the system

  `exclusions` optional list of collections to exclude from the export

  `exclusives` optional list of only collections to export. if only list is present exclusion
  list is ignored.
  """
  @derive [Poison.Encoder]
  defstruct ns: "", type: "", schemas: [], connection_opts: [], exclusions: [], exclusives: []

  @typedoc """
  Export type definition
  """
  @type t :: %Export{
          ns: String.t(),
          type: String.t(),
          connection_opts: term,
          schemas: term
        }

  @doc """
  Set up the Mnesia Database for `MoSQL` on disk
  This creates the necessary Schema, Database and
  Tables for MoSQL export data on disk for the specified
  erlang nodes so export definitions are persisted across
  application restarts. Note that this call will stop
  the `:mnesia` application. If no argument is provided,
  the database is created for the current node.

  Setup has to be performed from the console
  ```
  iex> MS.Export.setup!()
  :ok
  ```
  *NOTE*: This needs to be done only once and not every time the
  application starts. It also makes sense to create a helper
  function or mix task to do this
  """
  @spec setup!(nodes :: list(node)) :: :ok
  def setup!(nodes \\ [node()]) do
    # Create the DB directory (if custom path given)
    if path = Application.get_env(:mnesia, :dir) do
      :ok = File.mkdir_p!(path)
    end

    # Create the Schema
    Memento.stop()
    Memento.Schema.create(nodes)
    Memento.start()

    MS.DB.Export.create(disc_copies: nodes)
    MS.DB.Schema.create(disc_copies: nodes)
  end

  @doc """
  Creates a new export definition based on the given namespace and type
  namespace should be unique among all the exports saved in the system
  """
  def new(namespace, type, options \\ []) do
    case fetch(namespace, type) do
      {:error, :not_found} -> create(namespace, type, options)
      {:ok, _} -> {:error, :already_exists}
    end
  end

  @doc """
  Save the export to the persistent store
  """
  def save(ex) do
    MS.DB.Export.write(ex)
  end

  @doc """
  Fetch the saved export for the given namespace and type.
  """
  @spec fetch(String.t(), String.t()) :: {:ok, %MS.Export{}} | {:error, :not_found}
  def fetch(namespace, type) do
    Logger.info("Fetching export data #{namespace}.#{type}")
    MS.DB.Export.read(namespace, type) |> fetch_export_results()
  end

  defp fetch_export_results(_ = []), do: {:error, :not_found}

  defp fetch_export_results(result) do
    ex = Enum.map(result, &from_db(&1)) |> Enum.at(0)
    {:ok, ex}
  end

  defp from_db(db_ex) do
    ex = %Export{
      ns: db_ex.ns,
      type: db_ex.type,
      connection_opts: db_ex.connection_opts,
      exclusives: db_ex.exclusives,
      exclusions: db_ex.exclusions
    }

    schemas = MS.DB.Schema.read_all(db_ex.id) |> fetch_schema_results()
    %{ex | schemas: schemas}
  end

  defp fetch_schema_results(_ = []), do: {:error, :not_found}

  defp fetch_schema_results(result) do
    ex = Enum.map(result, &from_db(&1)) |> Enum.at(0)
    {:ok, ex}
  end

  @doc """
  Update the saved export for the given namespace and type
  """
  def update(namespace, type, export) do
    IO.puts("fetch #{namespace} and #{type} #{export.ns}")
  end

  @doc """
  Add list of collections to exclude from the export. Schema definition
  generation is also skipped for these excluded collections
  """
  def add_exclusions(namespace, type, exclusions) do
    case fetch(namespace, type) do
      {:ok, nil} ->
        {:error, :export_not_found}

      {:ok, export} ->
        export = %{export | exclusions: exclusions}
        update(namespace, type, export)
        {:ok, export}
    end
  end

  @doc """
  Add a list of only collections to export. If this is present all the other collections
  are excluded by default even if exclusion list is present
  """
  def add_exclusives(namespace, type, exclusives) do
    case fetch(namespace, type) do
      {:ok, nil} ->
        {:error, :export_not_found}

      {:ok, export} ->
        export = %{export | exclusives: exclusives}
        update(namespace, type, export)

        {:ok, export}
    end
  end

  @doc """
  Generate schema mappings for the given export
  """
  def generate_schema_mappings(export) do
    colls = final_collection_list(export)
    Enum.map(colls, &generate_schema_map(export.ns, &1))
  end

  @doc """
  Populate the schema store (`MS.Store`) for the data export process
  """
  def populate_schema_store(export) do
    Enum.each(export.schemas, &Schema.populate_schema_store(&1))
  end

  @doc """
  Saves the raw JSON for the export
  """
  def to_json(export, export_path) do
    Enum.each(export.schemas, &export_schema(export_path, &1))
  end

  defp has_exclusives?(export) do
    Enum.count(export.exclusives) > 0
  end

  defp has_exclusions?(export) do
    Enum.count(export.exclusions) > 0
  end

  defp create(namespace, type, options) do
    defaults = [connection_opts: [], exclusions: [], exclusives: []]
    merged_options = Keyword.merge(defaults, options) |> Enum.into(%{})

    export = %Export{
      ns: namespace,
      type: type,
      connection_opts: merged_options.connection_opts,
      exclusions: merged_options.exclusions,
      exclusives: merged_options.exclusives
    }

    {:ok, export}
  end

  ## Generates the final list of collection for the export based on the
  ## exclusions and exclusives
  defp final_collection_list(export) do
    collections = Mongo.collections()

    cond do
      has_exclusives?(export) -> filter_exclusives(collections, export.exclusives)
      has_exclusions?(export) -> filter_exclusions(collections, export.exclusions)
      true -> collections
    end
  end

  ## good to loop over actual collections to avoid typos on exclusives
  defp filter_exclusives(collections, exclusives) do
    Enum.filter(collections, &Enum.member?(exclusives, &1))
  end

  ## good to loop over actual collections to avoid typos on exclusives
  defp filter_exclusions(collections, exclusions) do
    Enum.filter(collections, fn coll -> Enum.member?(exclusions, coll) == false end)
  end

  @doc """
  Generate  a default schema mapping for a collection based on the given collection name
  """
  def generate_schema_map(namespace, collection) do
    Logger.info("Generating schema for namespace #{namespace} and collection #{collection}")

    schema = %Schema{
      ns: namespace,
      collection: collection,
      table: Macro.underscore(collection),
      indexes: [],
      primary_keys: [],
      mappings: []
    }

    flat_document = Mongo.flat_collection(collection)

    mappings = flat_document |> Map.keys() |> generate_mappings(flat_document)
    %{schema | mappings: mappings}
  end

  defp generate_mappings(keys, flat_document) do
    Enum.map(keys, &generate_field_mapping(&1, flat_document))
  end

  defp generate_field_mapping(key, flat_document) do
    sql_type = extract_sql_type(key, flat_document)
    sql_column = key_to_column_name(key)
    field_mapping_for_key(key, sql_column, sql_type)
  end

  defp field_mapping_for_key(key = "_id", sql_column, sql_type) do
    %Schema.Mapping{
      mongo_key: key,
      sql_column: sql_column,
      sql_type: sql_type,
      primary_key: true
    }
  end

  defp field_mapping_for_key(key, sql_column, sql_type) do
    %Schema.Mapping{
      mongo_key: key,
      sql_column: sql_column,
      sql_type: sql_type
    }
  end

  defp extract_sql_type(key, flat_document) do
    val = Map.get(flat_document, key)
    mongo_type = MS.Mongo.Type.typeof(val)
    SQL.mongo_to_sql_type(mongo_type)
  end

  defp key_to_column_name(_ = "_id"), do: "id"

  defp key_to_column_name(key) do
    Macro.underscore(key) |> String.replace("/", "_")
  end

  # export single schema file
  defp export_schema(path, schema) do
    :ok = File.write!("#{path}/#{schema.collection}.json", Poison.encode!(schema, pretty: true))
  end
end

defmodule MS.DB.Export do
  alias MS.DB.Schema

  use Memento.Table,
    attributes: [:id, :ns, :type, :connection_opts, :exclusions, :exclusives],
    index: [:ns, :type],
    type: :ordered_set,
    autoincrement: true

  def create(opts) do
    Memento.Table.create!(__MODULE__, opts)
  end

  def write(ex) do
    Memento.transaction!(fn ->
      db_ex = to_db(ex)
      db_ex = Memento.Query.write(db_ex)
      write_schemas(db_ex.id, ex.schemas)
    end)
  end

  def read(ns, type) do
    query = [
      {:==, :ns, ns},
      {:==, :type, type}
    ]

    Memento.transaction!(fn ->
      Memento.Query.select(MS.DB.Export, query)
    end)
  end

  defp write_schemas(_, _ = []) do
    []
  end

  defp write_schemas(export_id, schemas) do
    Enum.each(schemas, &Schema.write(export_id, &1))
  end

  defp to_db(ex) do
    %__MODULE__{
      ns: ex.ns,
      type: ex.type,
      connection_opts: ex.connection_opts,
      exclusions: ex.exclusions,
      exclusives: ex.exclusives
    }
  end
end
