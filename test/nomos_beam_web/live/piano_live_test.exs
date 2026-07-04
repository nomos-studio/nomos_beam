# SPDX-FileCopyrightText: 2025-2026 nomos-studio contributors
#
# SPDX-License-Identifier: EPL-2.0

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

  test "txlog viewer section is present", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/")
    assert html =~ "ctrl-tree txlog"
    assert html =~ "waiting for ctrl-tree events"
  end

  test "display_frame event appends entries to txlog viewer", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")

    send(view.pid, {:display_frame, [
      %{path: [:input, :keyboard, :key_down], value: "a", beat: 1.0}
    ]})

    html = render(view)
    assert html =~ ":input :keyboard :key_down"
    assert html =~ "1.00"
  end
end
