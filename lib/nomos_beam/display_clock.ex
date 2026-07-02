defmodule NomosBeam.DisplayClock do
  @moduledoc """
  5 Hz display frame clock. On each tick, drains the TxlogBuffer and broadcasts
  any new entries via PubSub on \"nomos:display:frame\".

  This is the universal push cadence for all live UI matter — no panel receives
  data faster than this rate. Subscribing LiveViews receive {:display_frame, entries}
  where entries is a (possibly empty) list of ctrl-tree echo maps in chronological
  order. LiveViews that receive an empty list should simply ignore the tick.
  """

  use GenServer

  @interval 200
  @topic "nomos:display:frame"

  def start_link(_opts), do: GenServer.start_link(__MODULE__, [], name: __MODULE__)

  @impl true
  def init(_opts) do
    send(self(), :tick)
    {:ok, %{}}
  end

  @impl true
  def handle_info(:tick, state) do
    case NomosBeam.TxlogBuffer.drain() do
      [] ->
        :ok

      entries ->
        Phoenix.PubSub.broadcast(NomosBeam.PubSub, @topic, {:display_frame, entries})
    end

    Process.send_after(self(), :tick, @interval)
    {:noreply, state}
  end
end
