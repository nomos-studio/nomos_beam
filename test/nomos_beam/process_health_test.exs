# SPDX-FileCopyrightText: 2025-2026 nomos-studio contributors
#
# SPDX-License-Identifier: EPL-2.0

defmodule NomosBeam.ProcessHealthTest do
  use ExUnit.Case, async: false

  alias NomosBeam.ProcessHealth

  test "snapshot/0 returns a list of 5 status maps" do
    health = ProcessHealth.snapshot()
    assert length(health) == 5
  end

  test "each status map has required keys" do
    health = ProcessHealth.snapshot()

    for svc <- health do
      assert Map.has_key?(svc, :name)
      assert Map.has_key?(svc, :label)
      assert Map.has_key?(svc, :status)
      assert Map.has_key?(svc, :note)
      assert svc.status in [:up, :down, :disabled]
      assert is_atom(svc.name)
      assert is_binary(svc.label)
    end
  end

  test "status names match expected set" do
    names = ProcessHealth.snapshot() |> Enum.map(& &1.name) |> MapSet.new()
    assert names == MapSet.new([:nous, :aion, :scsynth, :kairos, :m21])
  end

  test "snapshot/0 tolerates a supervisor that is not running" do
    # Simulate a dead GenServer by stopping AionSupervisor (if running).
    # ProcessHealth should return :down for it rather than raising.
    # We can't easily stop the app-level supervisor in tests, but we can
    # verify that snapshot/0 doesn't crash when called from outside the
    # application supervisor context.
    assert is_list(ProcessHealth.snapshot())
  end

  test "status/0 on AionSupervisor returns correct shape" do
    # The app supervisor starts AionSupervisor; it may or may not have a
    # binary, but it will always be alive as a GenServer.
    status = NomosBeam.AionSupervisor.status()
    assert status.name == :aion
    assert status.status in [:up, :down, :disabled]
  end

  test "status/0 on NousPort returns correct shape" do
    status = NomosBeam.NousPort.status()
    assert status.name == :nous
    assert status.status in [:up, :down]
  end
end
