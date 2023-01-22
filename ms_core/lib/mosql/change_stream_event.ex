defmodule Mosql.ChangeStreamEvent do
  @moduledoc """
  Represents change stream event in a simpler format needed for MOSQL
  """
  defstruct id: nil, document: nil, db: nil, coll: nil, operation_type: nil, raw_event_data: nil

  @typedoc """
  ChangeStream type definition
  """
  @type t :: %__MODULE__{
          id: String.t(),
          db: String.t(),
          coll: String.t(),
          document: term,
          operation_type: String.t(),
          raw_event_data: term
        }

  require Logger
  alias Broadway.{Message, Acknowledger}

  @behaviour Acknowledger

  @doc """
  Process the change event document from the Mongo change stream.
  Change event spec (https://www.mongodb.com/docs/manual/reference/change-events/):
  `
    {
      _id : { <BSON Object> },
      "operationType" : "<operation>",
      "fullDocument" : { <document> },
      "ns" : {
          "db" : "<database>",
          "coll" : "<collection>"
      },
      "to" : {
          "db" : "<database>",
          "coll" : "<collection>"
      },
      "documentKey" : { "_id" : <value> },
      "updateDescription" : {
          "updatedFields" : { <document> },
          "removedFields" : [ "<field>", ... ],
          "truncatedArrays" : [
            { "field" : <field>, "newSize" : <integer> },
            ...
          ]
      },
      "clusterTime" : <Timestamp>,
      "txnNumber" : <NumberLong>,
      "lsid" : {
          "id" : <UUID>,
          "uid" : <BinData>
      }
    }
  `
  """
  def parse_message(
        %{
          "documentKey" => %{"_id" => id},
          "clusterTime" => cluster_timestamp,
          "fullDocument" => document,
          "ns" => %{"coll" => coll, "db" => db},
          "operationType" => operation_type
        } = change_event
      ) do
    Logger.info("document id: #{inspect(id)}")
    Logger.info("cluster timestamp: #{inspect(cluster_timestamp.value)}")
    Logger.info("database: #{inspect(db)}")
    Logger.info("collection: #{inspect(coll)}")
    Logger.info("operation type: #{inspect(operation_type)}")

    ch = %__MODULE__{
      id: id,
      document: document,
      db: db,
      coll: coll,
      operation_type: operation_type,
      raw_event_data: change_event
    }

    metadata = Map.delete(ch, :document) |> Map.delete(:raw_event)
    ack_ref = "#{db}.#{coll}.#{string_id(id)}"
    acknowledger = build_acknowledger(ch, ack_ref)
    %Message{data: ch, metadata: metadata, acknowledger: acknowledger}
  end

  @impl Acknowledger
  def configure(ack_ref, ack_data, options) do
    Logger.info("configure acknowledger, ack_ref: #{inspect(ack_ref)}")
    Logger.info("configure acknowledger, ack_data: #{inspect(ack_data)}")
    Logger.info("configure acknowledger, options: #{inspect(options)}")
    {:ok, Map.merge(ack_data, Map.new(options))}
  end

  @impl Acknowledger
  def ack(ack_ref, success_messages, failed_messages) do
    # ack_ref uniquely identifies the message
    Logger.info("ack ref: #{inspect(ack_ref)}")
    Logger.info("success messages: #{inspect(success_messages)}")
    Logger.info("failed messages: #{inspect(failed_messages)}")
  end

  defp build_acknowledger(ch, ack_ref) do
    receipt = %{id: ch.id, receipt_handle: "receipt-#{string_id(ch.id)}"}
    {__MODULE__, ack_ref, %{receipt: receipt}}
  end

  defp string_id(object_id) do
    BSON.ObjectId.encode!(object_id)
  end
end
