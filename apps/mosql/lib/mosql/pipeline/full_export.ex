defmodule MS.Pipeline.FullExport do
  @moduledoc """
  Documentation for `FullExport`.
  """
  use Broadway

  alias Broadway.Message
  alias MS.Pipeline.FullExportProducer

  require Logger

  def start_link(_opts) do
    {:ok, pid} =
      Broadway.start_link(__MODULE__,
        name: __MODULE__,
        producer: [
          module: {FullExportProducer, 1},
          transformer: {__MODULE__, :transform, []}
        ],
        processors: [
          default: [concurrency: 1]
        ],
        batchers: [
          default: [concurrency: 1, batch_size: 1]
        ]
      )

    Logger.info("full export pipeline pid #{inspect(pid)}")
    {:ok, pid}
  end

  @impl true
  def handle_message(_, message, _) do
    IO.puts("=====handler begin=======")
    Logger.debug("#{inspect(message)}")
    IO.puts("=====handler end=======")
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

  def transform(event, _opts) do
    IO.puts("Transform: #{inspect(event)}")

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