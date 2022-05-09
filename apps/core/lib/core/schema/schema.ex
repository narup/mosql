defmodule MS.Core.Schema do
  @enforce_keys [:collection, :table, :fields]

  @moduledoc """
  Represents the schema mapping between MongoDB collection and Postgres tabl
  """
  defstruct collection: nil, table: nil, indexes: [], fields: []

  @typedoc """
  Schema type definition
  """
  @type t :: %__MODULE__{
          collection: String.t(),
          table: String.t(),
          indexes: term,
          fields: term
        }
end

defmodule MS.Core.Schema.Field do
  @enforce_keys [:field, :column, :type]

  @moduledoc """
  Represents the field
  """
  defstruct field: "", column: "", type: nil

  @typedoc """
  Field type definition
  """
  @type t :: %__MODULE__{
          field: String.t(),
          column: String.t(),
          type: String.t()
        }
end
