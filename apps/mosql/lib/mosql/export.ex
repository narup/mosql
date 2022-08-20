defmodule MS.Export do
  alias __MODULE__

  alias MS.Store

  @moduledoc """
  Represents the export definition and other configurations of the export
  `ns` namespace has to be unique across the system

  `exclusions` optional list of collections to exclude from the export

  `exclusives` optional list of only collections to export. if only list is present exclusion
  list is ignored.
  """
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

  def has_exclusives?(export) do
    Enum.count(export.exclusives) > 0
  end

  def has_exclusions?(export) do
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

    Store.set("#{namespace}.export.#{type}", export)
    {:ok, export}
  end
end
