defmodule MS.Pipeline.FullExport do
  @moduledoc """
  Documentation for `FullExport`.
  """
  use Broadway

  alias ElixirSense.Plugins.Ecto.Schema
  alias Broadway.Message
  alias MS.Pipeline.FullExportProducer
  alias MS.Mongo
  alias MS.Schema
  alias MS.SQL

  require Logger

  @doc """
  Kick of the migration process for the given namespace
  """
  def trigger(ns) do
    FullExportProducer.trigger(ns)
  end

  def export_status(ns) do
    FullExportProducer.info_producer_status(ns)
  end

  def start_link(_opts) do
    {:ok, pid} =
      Broadway.start_link(__MODULE__,
        name: __MODULE__,
        producer: [
          module:
            {FullExportProducer,
             %{
               namespace: '',
               export_triggered: false,
               collections: [],
               exported_collections: [],
               demand_filled: 0,
               pending_demand: 0
             }},
          transformer: {__MODULE__, :transform, []}
        ],
        processors: [
          # all default values
          default: [concurrency: System.schedulers_online() * 2, max_demand: 10, min_demand: 5]
        ],
        batchers: [
          default: [concurrency: 1, batch_size: 1]
        ]
      )

    Logger.info("full export pipeline pid #{inspect(pid)}")
    {:ok, pid}
  end

  # Prepare the messages that contain the mongo collection names for the export.
  # Attach the Mongo.Stream cursor to fetch all the documents for each collection
  # on message data.
  @impl true
  def prepare_messages(messages, _context) do
    Logger.info("Handling callback `prepare_messages`. messages: #{inspect(messages)}}")

    # Update the message to include Mongo cursor to fetch all the reocrds lazily
    messages =
      Enum.map(messages, fn message ->
        coll = message.data[:collection]
        ns = message.data[:namespace]

        Logger.info("Fetching documents for the collection #{coll} in namespace #{ns}")

        cursor = Mongo.find_all(coll, 3)

        Message.update_data(message, fn _ ->
          %{namespace: ns, collection: coll, rows: cursor}
        end)
      end)

    messages
  end

  # Handle the export for each document of the collection
  @impl true
  def handle_message(processor, message, _context) do
    %{data: %{namespace: namespace, collection: collection, rows: cursor}} = message

    Logger.info(
      "Handling callback 'handle_message' for collection '#{collection}' with processor id #{processor}"
    )

    schema = %Schema{ns: namespace, collection: collection}

    Enum.to_list(cursor)
    |> Enum.each(fn doc ->
      flat_doc = Mongo.flat_document_map(doc)
      IO.inspect(flat_doc)

      sql = SQL.upsert_document_sql(schema, flat_doc)
      Logger.info("SQL: #{sql}")
    end)

    Message.put_batcher(message, :default)
  end

  @impl true
  def handle_batch(:default, messages, _batch_info, _context) do
    # Send batch of successful messages as ACKs to SQS
    # This tells SQS that this list of messages were successfully processed
    IO.puts("=====batcher begin=======")
    Logger.debug("#{inspect(messages)}")
    IO.puts("=====batcher end=======")
    Process.sleep(1000)
    IO.puts("=====FINAL OUTPUT=======")
    messages
  end

  # Producer transformer to transformer the event data generated by the producer
  # to %Broadway.Message{}
  def transform(event, opts) do
    IO.puts("Transform event: #{inspect(event)}, opts: #{inspect(opts)}")

    %Message{
      data: event,
      acknowledger: {__MODULE__, :ack_id, :ack_data}
    }
  end

  def ack(:ack_id, successful, failed) do
    # Write ack code here
    IO.puts("Ack: #{inspect(successful)} - #{inspect(failed)}")
    :ok
  end
end
