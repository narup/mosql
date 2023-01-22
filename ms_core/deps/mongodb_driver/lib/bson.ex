defmodule BSON do
  @moduledoc """
  Functions for encoding and decoding BSON documents.
  """

  @type t :: document | String.t() | atom | number | boolean | BSON.Binary.t() | BSON.ObjectId.t() | BSON.Regex.t() | BSON.JavaScript.t() | BSON.Timestamp.t() | BSON.LongNumber.t() | [t]
  @type document :: %{atom => BSON.t()} | %{String.t() => BSON.t()} | [{atom, BSON.t()}] | [{String.t(), BSON.t()}]

  @doc """
  Encode a BSON document to `iodata`.
  """
  @spec encode(document) :: iodata
  def encode(map) when is_map(map) do
    case Map.has_key?(map, :__struct__) do
      true -> BSON.Encoder.encode(Map.to_list(map))
      false -> BSON.Encoder.encode(map)
    end
  end

  def encode([{_, _} | _] = keyword) do
    BSON.Encoder.encode(keyword)
  end

  @doc """
  Decode `iodata` to a BSON document.
  """
  @spec decode(iodata) :: document
  def decode(iodata) do
    IO.iodata_to_binary(iodata)
    |> BSON.Decoder.decode()
  end
end
