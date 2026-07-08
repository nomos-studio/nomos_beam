# SPDX-FileCopyrightText: 2025-2026 nomos-studio contributors
#
# SPDX-License-Identifier: EPL-2.0

defmodule NomosBeam.DisplayClock do
  @moduledoc """
  5 Hz display frame clock. On each tick:
  - drains TxlogBuffer and broadcasts any new entries on "nomos:display:frame"
  - snapshots process health and broadcasts on "nomos:process:health"

  This is the universal push cadence for all live UI matter — no panel receives
  data faster than this rate.
  """

  use GenServer

  @interval 200
  @topic "nomos:display:frame"
  @health_topic "nomos:process:health"

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

    health = NomosBeam.ProcessHealth.snapshot()
    Phoenix.PubSub.broadcast(NomosBeam.PubSub, @health_topic, {:process_health, health})

    Process.send_after(self(), :tick, @interval)
    {:noreply, state}
  end
end
