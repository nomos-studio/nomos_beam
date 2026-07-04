# SPDX-FileCopyrightText: 2025-2026 nomos-studio contributors
#
# SPDX-License-Identifier: EPL-2.0

defmodule NomosBeam.NousPortTest do
  use ExUnit.Case, async: false

  # NousPort is already started by the application supervisor.
  # These tests verify the dispatch logic in isolation by sending
  # echo messages directly to the GenServer.

  setup do
    # Reset KeyboardServer state before each test.
    NomosBeam.KeyboardServer.clear_all()
    :ok
  end

  test "ctrl_write_echo for key_down calls KeyboardServer.key_down" do
    send(NomosBeam.NousPort, %{
      op: :ctrl_write_echo,
      path: [:input, :keyboard, :key_down],
      value: "a"
    })

    # Give the GenServer time to process the message.
    :timer.sleep(50)

    assert MapSet.member?(NomosBeam.KeyboardServer.pressed(), "a")
  end

  test "ctrl_write_echo for key_up calls KeyboardServer.key_up" do
    NomosBeam.KeyboardServer.key_down("a")

    send(NomosBeam.NousPort, %{
      op: :ctrl_write_echo,
      path: [:input, :keyboard, :key_up],
      value: "a"
    })

    :timer.sleep(50)

    refute MapSet.member?(NomosBeam.KeyboardServer.pressed(), "a")
  end
end
