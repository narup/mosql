defmodule MongoTest do
  use ExUnit.Case, async: true

  alias Mosql.Mongo

  require Logger

  @user_document %{
    "_id" => "6277f677b99d8078d17d5918",
    "attributes" => %{
      "communicationChannels" => %{
        "email" => "john.doe@johndoe.com",
        "phone" => "111222333"
      },
      "communicationPrefs" => "SMS",
      "phoneNumberVerified" => true,
      "randomAttributes" => %{
        "app_source" => "web",
        "channel" => "marketing",
        "signup_complete" => "false"
      },
      "skipTutorial" => false,
      "themeAttributes" => %{
        "appearance" => "dark",
        "automatic" => false,
        "color" => "#cc00ff"
      }
    },
    "city" => "San Francisco",
    "email" => "john.doe@johndoe.com",
    "name" => "John Doe",
    "state" => "CA",
    "zip" => "94113",
    "functions" => [],
    "tags" => ["mosql", "mongodb", "elixir", "broadway"],
    "prices" => [30, 50.50, "n/a"],
    "configs" => [%{key1: "value1", key2: "value2"}, %{key3: 20, key4: 42.99}]
  }

  test "mongo document lookup" do
    IO.inspect(@user_document["attributes"]["communicationChannels"]["email"])

    assert @user_document["attributes"]["communicationChannels"]["email"] ==
             "john.doe@johndoe.com"

    object_id = BSON.ObjectId.decode!(@user_document["_id"])
    document = %{@user_document | "_id" => object_id}
    result = Mongo.flat_document_map(document)
    IO.inspect(result)

    keys = Mongo.extract_document_keys(document)
    IO.inspect(keys)

    assert Enum.count(result) == Enum.count(keys)
  end
end
