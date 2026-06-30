defmodule NomosBeam.KeyboardServer do
  @moduledoc false
  use GenServer

  @topic "keyboard:events"

  def start_link(_opts), do: GenServer.start_link(__MODULE__, MapSet.new(), name: __MODULE__)

  def key_down(key), do: GenServer.cast(__MODULE__, {:key_down, key})
  def key_up(key), do: GenServer.cast(__MODULE__, {:key_up, key})
  def clear_all, do: GenServer.cast(__MODULE__, :clear_all)
  def pressed, do: GenServer.call(__MODULE__, :pressed)

  @impl true
  def init(state), do: {:ok, state}

  @impl true
  def handle_cast({:key_down, key}, pressed) do
    pressed = MapSet.put(pressed, key)
    Phoenix.PubSub.broadcast(NomosBeam.PubSub, @topic, {:keyboard_state, pressed})
    {:noreply, pressed}
  end

  def handle_cast({:key_up, key}, pressed) do
    pressed = MapSet.delete(pressed, key)
    Phoenix.PubSub.broadcast(NomosBeam.PubSub, @topic, {:keyboard_state, pressed})
    {:noreply, pressed}
  end

  def handle_cast(:clear_all, _pressed) do
    Phoenix.PubSub.broadcast(NomosBeam.PubSub, @topic, {:keyboard_state, MapSet.new()})
    {:noreply, MapSet.new()}
  end

  @impl true
  def handle_call(:pressed, _from, pressed), do: {:reply, pressed, pressed}
end
