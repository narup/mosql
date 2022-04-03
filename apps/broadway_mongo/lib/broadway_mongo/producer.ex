defmodule MS.BroadwayMongo.Producer do
  use GenStage

  require Logger
  alias MS.BroadwayMongo.ChangeStreamEvent

  @behaviour Broadway.Producer

  @collection "order"
  @supervisor_name MS.BroadwayMongo.DynamicSupervisor

  @impl true
  def init(args) do
    Logger.debug("args from broadway pipeline start: #{inspect(args)}")

    initial_state = %{
      last_resume_token: Keyword.fetch!(args, :last_resume_token),
      mongo_opts: Keyword.fetch!(args, :mongo_opts)
    }

    Logger.info("init mongo db change streamer with state: #{inspect(initial_state)}")

    Process.send_after(self(), :connect, 500)
    {:producer, initial_state}
  end

  @impl true
  def prepare_for_start(_module, broadway_opts) do
    Logger.info("prepare for start with broadway options #{inspect(broadway_opts)}")

    {producer_module, mongo_opts} = broadway_opts[:producer][:module]
    mongo_opts = Keyword.put(mongo_opts, :name, :mongo_broadway)

    broadway_opts_with_defaults =
      put_in(
        broadway_opts,
        [:producer, :module],
        {producer_module, [last_resume_token: nil, mongo_opts: mongo_opts]}
      )

    children = [
      {DynamicSupervisor, strategy: :one_for_one, name: @supervisor_name}
    ]

    {children, broadway_opts_with_defaults}
  end

  @impl true
  def handle_info(:connect, state) do
    Logger.info("connecting to MongoDB change stream with state #{inspect(state)}")

    {:ok, pid} = DynamicSupervisor.start_child(@supervisor_name, {Mongo, state.mongo_opts})
    Logger.info("mongo connection process #{inspect(pid)}")

    # Span a new process
    parent = self()

    watch = fn ->
      Enum.each(get_stream_cursor(parent, state), &new_change_stream_event(parent, &1))
    end

    pid = spawn(watch)

    # Monitor the process
    Process.monitor(pid)

    {:noreply, [], state}
  end

  @impl true
  def handle_info({:DOWN, _, :process, _pid, reason}, state) do
    Logger.info(
      "change stream cursor process is down: #{inspect(reason)}. retrying connecting again"
    )

    Process.send_after(self(), :connect, 3000)

    {:noreply, [], state}
  end

  @impl true
  def handle_demand(demand, state) do
    Logger.info("change streamer received more demand #{demand}")
    # ignore since documents received from change stream is sent via handle_cast
    {:noreply, [], state}
  end

  @impl true
  def handle_cast({:new_resume_token, token}, state) do
    Logger.info("storing new resume token #{inspect(token)} in the state")
    {:noreply, [], %{state | last_resume_token: token}}
  end

  @impl true
  def handle_cast({:new_change_event, raw_change_event}, state) do
    message = ChangeStreamEvent.parse_message(raw_change_event)
    Logger.info("send new document received to the processor")
    {:noreply, [message], state}
  end

  defp new_token(parent, %{"_data" => token}) do
    Logger.info("new resume token received: #{token}")
    GenStage.cast(parent, {:new_resume_token, token})
  end

  defp new_change_stream_event(parent, raw_event_data) do
    Logger.info("new change stream event received: #{inspect(raw_event_data)}")
    GenStage.cast(parent, {:new_change_event, raw_event_data})
  end

  defp get_stream_cursor(parent, %{last_resume_token: nil}) do
    Logger.info("watch the collection without resume token")

    Mongo.watch_collection(:mongo_broadway, @collection, [], &new_token(parent, &1),
      max_time: 2_000,
      full_document: "updateLookup"
    )
  end

  defp get_stream_cursor(parent, %{last_resume_token: resume_token}) do
    Logger.info("watch the collection using last resume token: #{inspect(resume_token)}")

    Mongo.watch_collection(:mongo_broadway, @collection, [], &new_token(parent, &1),
      full_document: "updateLookup",
      max_time: 2_000,
      resume_after: resume_token
    )
  end
end
