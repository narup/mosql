defmodule MS.Pipeline.Producer do
  use GenStage

  def start_link(number) do
    GenStage.start_link(__MODULE__, number)
  end

  def init(counter) do
    {:producer, counter}
  end

  def handle_demand(demand, counter) when demand > 0 do
    IO.puts("Handle demand #{demand}")
    events = []
    {:noreply, events, counter + demand}
  end
end
