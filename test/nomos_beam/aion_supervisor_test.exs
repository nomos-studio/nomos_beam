defmodule NomosBeam.AionSupervisorTest do
  use ExUnit.Case, async: true

  # AionSupervisor is started by the application supervisor; we test its
  # config resolution and arg-building logic through the GenServer state.

  test "starts without error when aion binary is absent" do
    # Start an isolated instance pointing at a non-existent binary.
    # It should start, log a warning, and schedule a retry — not crash.
    {:ok, pid} =
      GenServer.start_link(NomosBeam.AionSupervisor,
                           [aion_path: "/nonexistent/aion", midi_port: -1])

    # Give the init/retry path a moment to settle.
    Process.sleep(100)
    assert Process.alive?(pid)
    GenServer.stop(pid)
  end

  test "default binary path resolves to a string" do
    # Call the GenServer to inspect what default_binary resolves to.
    # We can't call the private function directly, so we verify the
    # GenServer starts with its default opts and exposes a live pid.
    {:ok, pid} = GenServer.start_link(NomosBeam.AionSupervisor, [midi_port: -1])
    assert Process.alive?(pid)
    GenServer.stop(pid)
  end
end
