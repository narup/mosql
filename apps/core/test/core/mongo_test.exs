defmodule MongoTest do
  use ExUnit.Case, async: true

  alias MS.Core.Mongo

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
    "zip" => "94113"
  }

  test "mongo document lookup" do
    IO.inspect(@user_document["attributes"]["communicationChannels"]["email"])
    assert @user_document["attributes"]["communicationChannels"]["email"] == "hello@mosql.io"

    result = Mongo.flat_document_map(@user_document)
    IO.inspect(result)

    keys = Mongo.extract_document_keys(result)
    IO.inspect(keys)

    assert Enum.count(result) == Enum.count(keys)
  end
end
