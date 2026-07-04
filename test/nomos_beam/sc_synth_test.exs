defmodule NomosBeam.ScSynthTest do
  use ExUnit.Case, async: true

  test "starts without error when sclang binary is absent" do
    {:ok, pid} =
      GenServer.start_link(NomosBeam.ScSynth,
                           [sc_path: "/nonexistent/sclang",
                            boot_script: "/nonexistent/sc-headless.scd"])

    Process.sleep(100)
    assert Process.alive?(pid)
    GenServer.stop(pid)
  end

  test "starts without error when boot script is absent" do
    {:ok, pid} =
      GenServer.start_link(NomosBeam.ScSynth,
                           [sc_path: "/Applications/SuperCollider.app/Contents/MacOS/sclang",
                            boot_script: "/nonexistent/sc-headless.scd"])

    Process.sleep(100)
    assert Process.alive?(pid)
    GenServer.stop(pid)
  end

  test "disabled by default when NOMOS_STUDIO_SRC is unset" do
    # This test assumes the env var is not set in CI.
    if System.get_env("NOMOS_STUDIO_SRC") == nil do
      {:ok, pid} = GenServer.start_link(NomosBeam.ScSynth, [])
      Process.sleep(50)
      assert Process.alive?(pid)
      GenServer.stop(pid)
    end
  end
end
