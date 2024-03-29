defmodule Mosql.Export do
  alias Mosql.Schema
  alias Mosql.SQL
  alias Mosql.Mongo

  alias __MODULE__

  require Logger
  require Memento

  @moduledoc """
  Represents the export definition and other configurations of the export
  `ns` namespace has to be unique across the system.

  `exclusions` optional list of collections to exclude from the export

  `exclusives` optional list of only collections to export. if only list is present exclusion
  list is ignored.

  `source_db_opts` and `destination_db_opts` contains the source and destination
   database details. It's a keyword list with following optional keys:
      `db_name`
      `connection_url`
  """
  @derive [Poison.Encoder]
  defstruct ns: "",
            type: "",
            schemas: [],
            exclusions: [],
            exclusives: [],
            mongo_opts: [],
            postgres_opts: []

  @typedoc """
  Export type definition
  """
  @type t :: %Export{
          ns: String.t(),
          type: String.t(),
          schemas: term,
          exclusions: term,
          exclusives: term,
          mongo_opts: term,
          postgres_opts: term
        }

  @doc """
  Set up the Mnesia Database for `Mosql` on disk
  This creates the necessary Schema, Database and
  Tables for MoSQL export data on disk for the specified
  erlang nodes so export definitions are persisted across
  application restarts. Note that this call will stop
  the `:mnesia` application. If no argument is provided,
  the database is created for the current node.

  Setup has to be performed from the console
  ```
  iex> Mosql.Export.setup!()
  :ok
  ```
  *NOTE*: This needs to be done only once and not every time the
  application starts. It also makes sense to create a helper
  function or mix task to do this
  """
  @spec setup!(nodes :: list(node)) :: :ok
  def setup!(nodes \\ [node()]) do
    # Create the Schema
    Memento.stop()
    Memento.Schema.create(nodes)
    Memento.start()

    Mosql.DB.Export.create(disc_copies: nodes)
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
    Mosql.DB.Export.write(ex)
  end

  @doc """
  Delete the export for the given namespace and type
  """
  def delete(namespace, type) do
    Mosql.DB.Export.delete(namespace, type)
  end

  @doc """
  Fetch the saved export for the given namespace and type.
  """
  @spec fetch(String.t(), String.t()) :: {:ok, %Mosql.Export{}} | {:error, :not_found}
  def fetch(namespace, type) do
    Logger.info("Fetching export data #{namespace}.#{type}")
    Mosql.DB.Export.read(namespace, type) |> fetch_export_result()
  end

  def fetch_all() do
    Logger.info("Fetching all the saved exports")
    Mosql.DB.Export.read_all() |> Enum.map(&from_db(&1))
  end

  defp fetch_export_result(_ = []), do: {:error, :not_found}

  defp fetch_export_result(result) do
    ex = Enum.map(result, &from_db(&1)) |> Enum.at(0)
    {:ok, ex}
  end

  defp from_db(db_ex) do
    %Export{
      ns: db_ex.ns,
      type: db_ex.type,
      schemas: db_ex.schemas,
      exclusives: db_ex.exclusives,
      exclusions: db_ex.exclusions,
      mongo_opts: db_ex.mongo_opts,
      postgres_opts: db_ex.postgres_opts
    }
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
  Generate schema mappings for the given export based on the collection
  data fields. Default alphabetical sorting is applied to the schema based
  on the collection names. Collection fields will follow a sorting order of
  the primary key(s) such as id and then the order based on the field types
  """
  def generate_schema_mappings(export) do
    export
    |> final_collection_list()
    |> Enum.map(&generate_schema_map(export.ns, &1))
    |> Schema.sort_schemas()
  end

  @doc """
  Populate the schema store (`Mosql.Store`) for the data export process
  """
  def populate_schema_store(export) do
    Schema.init_schema_store(export.ns)
    Enum.each(export.schemas, &Schema.populate_schema_store(&1))
  end

  @doc """
  Retruns the name of the destination database
  TODO: fetch the db details from export.destination_db_opts
  """
  def destination_db_name(export) do
    export.postgres_opts[:database]
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
    defaults = [connection_opts: [], schemas: [], exclusions: [], exclusives: []]
    merged_options = Keyword.merge(defaults, options) |> Enum.into(%{})

    export = %Export{
      ns: namespace,
      type: type,
      schemas: merged_options.schemas,
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
    mongo_type = Mongo.Type.typeof(val)
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

defmodule Mosql.DB.Export do
  use Memento.Table,
    attributes: [
      :id,
      :ns,
      :type,
      :schemas,
      :exclusions,
      :exclusives,
      :mongo_opts,
      :postgres_opts
    ],
    index: [:ns, :type],
    type: :ordered_set,
    autoincrement: true

  def create(opts) do
    Memento.Table.create!(__MODULE__, opts)
  end

  def write(ex) do
    Memento.transaction!(fn ->
      db_ex = to_db(ex)
      Memento.Query.write(db_ex)
    end)
  end

  def read(ns, type) do
    query = [
      {:==, :ns, ns},
      {:==, :type, type}
    ]

    Memento.transaction!(fn ->
      Memento.Query.select(Mosql.DB.Export, query)
    end)
  end

  def read_all do
    Memento.transaction!(fn ->
      Memento.Query.all(Mosql.DB.Export)
    end)
  end

  def delete(ns, type) do
    result = read(ns, type)

    if Enum.count(result) > 0 do
      Memento.transaction!(fn ->
        Memento.Query.delete_record(Enum.at(result, 0))
      end)
    end
  end

  defp to_db(ex) do
    %__MODULE__{
      ns: ex.ns,
      type: ex.type,
      schemas: ex.schemas,
      exclusions: ex.exclusions,
      exclusives: ex.exclusives,
      mongo_opts: ex.mongo_opts,
      postgres_opts: ex.postgres_opts
    }
  end
end
