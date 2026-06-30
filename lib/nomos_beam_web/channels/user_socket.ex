defmodule NomosBeamWeb.UserSocket do
  use Phoenix.Socket

  channel "keyboard:*", NomosBeamWeb.KeyboardChannel

  @impl true
  def connect(_params, socket, _connect_info), do: {:ok, socket}

  @impl true
  def id(_socket), do: nil
end
