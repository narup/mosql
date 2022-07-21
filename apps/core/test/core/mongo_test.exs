defmodule MongoTest do
  use ExUnit.Case, async: true

  alias MS.Core.Mongo

  require Logger

  @user_document %{
    "_id" => "6277f677b99d8078d17d5918",
    "attributes" => %{
      "communicationChannels" => %{
        "email" => "hello@mosql.io",
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
    "city" => "Hanover",
    "email" => "hello@puran.me",
    "name" => "Puran Sarki",
    "state" => "NJ",
    "zip" => "07981"
  }

  test "mongo document lookup" do
    IO.inspect(@user_document["attributes"]["communicationChannels"]["email"])
    assert @user_document["attributes"]["communicationChannels"]["email"] == "hello@mosql.io"

    result = Mongo.flat_document_map(@user_document)
    IO.inspect(result)
  end
end
