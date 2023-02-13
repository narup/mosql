defmodule Mosql.Util do
  def is_blank?(data), do: is_nil(data) || Regex.match?(~r/\A\s*\z/, data)
end
