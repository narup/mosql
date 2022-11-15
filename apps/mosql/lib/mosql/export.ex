defmodule MS.Export do
  alias __MODULE__

  alias MS.Store
  alias MS.Schema
  alias MS.Schema.{SQL}
  alias MS.Mongo

  require Logger

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
  @type t :: %__MODULE__{
          ns: String.t(),
          type: String.t(),
          connection_opts: term,
          schemas: term
        }

  @doc """
  Creates a new export definition based on the given namespace and type
  namespace should be unique among all the exports saved in the system
  """
  def new(namespace, type, options \\ []) do
    case fetch(namespace, type) do
      {:ok, nil} -> create(namespace, type, options)
      _ -> {:error, :already_exists}
    end
  end

  def create(namespace, type, options) do
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

  def save(export) do
    Store.set("#{export.ns}.export.#{export.type}", export)
  end

  @doc """
  Fetch the saved export for the given namespace and type. Returns nil if there's none exists
  """
  def fetch(namespace, type) do
    {:ok, Store.get_if_exists("#{namespace}.export.#{type}", nil)}
  end

  @doc """
  Update the saved export for the given namespace and type
  """
  def update(namespace, type, export) do
    Store.set("#{namespace}.export.#{type}", export)
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
