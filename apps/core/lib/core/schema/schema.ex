defmodule MS.Core.Schema do
  @moduledoc """
  Represents the schema mapping between MongoDB collection and Postgres tabl
  """
  defstruct collection: "", table: "", indexes: [], fields: []

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
