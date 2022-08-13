defmodule MS.Export do
  alias __MODULE__

  alias MS.Store

  @moduledoc """
  Represents the export definition and configurations
  """
  defstruct ns: "", type: "", schemas: [], connection_opts: []

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
  def new(namespace, type) do
    case fetch(namespace, type) do
      nil -> create(namespace, type)
      _ -> :already_exists
    end
  end

  @doc """
  Fetch the saved export for the given namespace and type. Returns nil if there's none exists
  """
  def fetch(namespace, type) do
    Store.get_if_exists("#{namespace}.export.#{type}", nil)
  end

  @doc """
  Update the saved export for the given namespace and type
  """
  def update(namespace, type, export) do
    Store.set("#{namespace}.export.#{type}", export)
  end

  defp create(namespace, type) do
    export = %Export{ns: namespace, type: type}
    Store.set("#{namespace}.export.#{type}", export)
    export
  end

end
