defmodule MS.BroadwayMongo.Producer do
  use GenStage

  require Logger
  alias MS.BroadwayMongo.ChangeStreamEvent

  @behaviour Broadway.Producer

  @collection "users"
  @supervisor_name MS.BroadwayMongo.DynamicSupervisor

  @doc """
  Invoked once by Broadway during Broadway.start_link/2.
  see more here https://hexdocs.pm/broadway/Broadway.Producer.html#c:prepare_for_start/2

  @broadway_opts [
    hibernate_after: 15000,
    context: :context_not_set,
    resubscribe_interval: 100,
    max_seconds: 5,
    max_restarts: 3,
    shutdown: 30000,
    name: MS.Pipeline,
    producer: [
      hibernate_after: 15000,
      transformer: nil,
      concurrency: 1,
      module:
        {MS.BroadwayMongo.Producer, <producer_opts>}
    ],
    processors: [default: [hibernate_after: 15000, max_demand: 10, concurrency: 1]],
    batchers: [
      default: [hibernate_after: 15000, batch_timeout: 1000, concurrency: 1, batch_size: 1]
    ]
  ]
  """
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
  def init(args) do
    Logger.debug("args from broadway pipeline start: #{inspect(args)}")

    initial_state = %{
      last_resume_token: Keyword.fetch!(args, :last_resume_token),
      mongo_opts: Keyword.fetch!(args, :mongo_opts)
    }

    Logger.info("init mongo db change streamer with state: #{inspect(initial_state)}")

    Process.send_after(self(), :connect, 500)

    pid = self()
    Logger.info("producer process id #{inspect(pid)}")

    {:producer, initial_state}
  end

  @impl true
  def handle_info(:connect, state) do
    mongo_pid = connect_mongo(state)
    Process.monitor(mongo_pid)

    state = Map.put(state, :mongo_pid, mongo_pid)

    main_pid = self()
    # spawn a new process to watch the streaming cursor and monitor it
    cursor_pid =
      spawn(fn ->
        Enum.each(get_stream_cursor(main_pid, state), &new_change_stream_event(main_pid, &1))
      end)

    Process.monitor(cursor_pid)

    state = Map.put(state, :cursor_pid, cursor_pid)

    Logger.info("watching change streams in a background process #{inspect(cursor_pid)}")

    {:noreply, [], state}
  end

  @impl true
  def handle_info({:DOWN, _, :process, pid, reason}, state) do
    Logger.info(":DOWN signal received for pid: #{inspect(pid)}")

    if state.mongo_pid == pid do
      Logger.info(
        ":DOWN signal received from mongo process: #{inspect(reason)}. retrying connecting again"
      )
    else
      Logger.info(
        ":DOWN signal received from mongo cursor process: #{inspect(reason)}. retrying connecting again"
      )
    end

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
    Logger.debug("storing new resume token #{inspect(token)} in the state")
    {:noreply, [], %{state | last_resume_token: token}}
  end

  @impl true
  def handle_cast({:new_change_stream_event, raw_change_stream_event}, state) do
    message = ChangeStreamEvent.parse_message(raw_change_stream_event)
    Logger.info("send new document received to the processor")
    {:noreply, [message], state}
  end

  defp new_token(parent, %{"_data" => token}) do
    Logger.debug("new resume token received: #{token}")
    GenStage.cast(parent, {:new_resume_token, token})
  end

  defp new_change_stream_event(parent, raw_event_data) do
    Logger.info("new change stream event received")
    Logger.debug("#{inspect(raw_event_data)}")
    GenStage.cast(parent, {:new_change_stream_event, raw_event_data})
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
      resume_after: %{"_data" => resume_token}
    )
  end

  defp connect_mongo(state) do
    case DynamicSupervisor.start_child(@supervisor_name, {Mongo, state.mongo_opts}) do
      {:ok, pid} ->
        Logger.info("mongo connection process #{inspect(pid)}")
        pid

      {:error, {:already_started, pid}} ->
        Logger.info("using existing mongo connection process #{inspect(pid)}")
        pid
    end
  end
end
