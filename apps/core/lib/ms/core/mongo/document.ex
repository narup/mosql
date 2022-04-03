defmodule MS.Core.Mongo.Document do
  def string_id(object_id) do
    BSON.ObjectId.encode!(object_id)
  end
end
