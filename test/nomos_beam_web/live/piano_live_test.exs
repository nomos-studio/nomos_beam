defmodule NomosBeamWeb.PianoLiveTest do
  use NomosBeamWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  test "renders piano keyboard", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/")
    assert html =~ "piano-key white"
    assert html =~ "piano-key black"
    assert html =~ "c-natural"
  end

  test "key_down highlights the key, key_up un-highlights it", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")

    # Send the PubSub message directly — tests LiveView reaction without timing
    # dependency on the GenServer cast + PubSub delivery chain.
    send(view.pid, {:keyboard_state, MapSet.put(MapSet.new(), "a")})
    assert render(view) =~ ~r/piano-key white c-natural pressed/

    send(view.pid, {:keyboard_state, MapSet.new()})
    refute render(view) =~ ~r/piano-key white c-natural pressed/
  end

  test "all 12 chromatic keys are rendered", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/")
    for phys <- ~w[a w s e d f t g y h u j] do
      assert html =~ phys, "expected physical key #{inspect(phys)} in piano HTML"
    end
  end
end
