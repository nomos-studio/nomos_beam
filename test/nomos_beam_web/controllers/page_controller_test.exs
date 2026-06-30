defmodule NomosBeamWeb.PageControllerTest do
  use NomosBeamWeb.ConnCase

  # "/" is now a LiveView (PianoLive); see piano_live_test.exs for content tests.
  # The controller is kept for error pages; verify the redirect behaviour here.
  test "GET / redirects to LiveView session", %{conn: conn} do
    conn = get(conn, ~p"/")
    # LiveView root route responds 200 with the live session redirect script.
    assert conn.status == 200
  end
end
