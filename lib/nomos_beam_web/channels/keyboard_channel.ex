defmodule NomosBeamWeb.KeyboardChannel do
  use Phoenix.Channel

  @impl true
  def join("keyboard:tauri", _payload, socket), do: {:ok, socket}

  @impl true
  def handle_in("key_event", %{"op" => "key_down", "key" => key}, socket) do
    NomosBeam.KeyboardServer.key_down(key)
    {:noreply, socket}
  end

  def handle_in("key_event", %{"op" => "key_up", "key" => key}, socket) do
    NomosBeam.KeyboardServer.key_up(key)
    {:noreply, socket}
  end

  @impl true
  def terminate(_reason, _socket) do
    # Tauri window closed or WS dropped — release all held keys to avoid stuck notes.
    NomosBeam.KeyboardServer.clear_all()
    :ok
  end
end
