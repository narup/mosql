defmodule MS.Pipeline.ChangeStream do
  @moduledoc """
  Documentation for `ChangeStreamPipeline`.
  """
  use Broadway

  alias Broadway.Message
  require Logger

  def start_link(_opts) do
    {:ok, pid} =
      Broadway.start_link(__MODULE__,
        name: __MODULE__,
        producer: [
          module: Application.fetch_env!(:pipeline, :producer_module)
        ],
        processors: [
          default: [concurrency: 1]
        ],
        batchers: [
          default: [concurrency: 1, batch_size: 1]
        ]
      )

    Logger.info("pipeline pid #{inspect(pid)}")
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
    Process.sleep(4000)
    IO.puts("=====FINAL OUTPUT=======")
    messages
  end
end
