defmodule MS.Pipeline do
  @moduledoc """
  Documentation for `Pipeline`.
  """
  use Broadway

  alias Broadway.Message

  def start_link(_opts) do
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
  end

  @impl true
  def handle_message(_, message, _) do
    IO.puts("=====handler begin=======")
    IO.inspect(message)
    IO.puts("=====handler end=======")
    Message.put_batcher(message, :default)
  end

  @impl true
  def handle_batch(:default, messages, _batch_info, _context) do
    # Send batch of successful messages as ACKs to SQS
    # This tells SQS that this list of messages were successfully processed
    IO.puts("=====batcher begin=======")
    IO.inspect(messages)
    IO.puts("=====batcher end=======")
    Process.sleep(4000)
    IO.puts("=====FINAL OUTPUT=======")
    messages
  end

  @doc """
  Hello world.

  ## Examples

      iex> Pipeline.hello()
      :world

  """
  def hello do
    :world
  end
end
