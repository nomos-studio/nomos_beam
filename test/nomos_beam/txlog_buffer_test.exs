# SPDX-FileCopyrightText: 2025-2026 nomos-studio contributors
#
# SPDX-License-Identifier: EPL-2.0

defmodule NomosBeam.TxlogBufferTest do
  use ExUnit.Case, async: true

  # TxlogBuffer is started by the application supervisor.
  # Each test drains the buffer first to start from a clean state.

  setup do
    NomosBeam.TxlogBuffer.drain()
    :ok
  end

  test "drain returns entries in chronological order" do
    NomosBeam.TxlogBuffer.push(%{path: [:a], value: "first",  beat: 1.0})
    NomosBeam.TxlogBuffer.push(%{path: [:b], value: "second", beat: 2.0})
    NomosBeam.TxlogBuffer.push(%{path: [:c], value: "third",  beat: 3.0})

    entries = NomosBeam.TxlogBuffer.drain()
    beats = Enum.map(entries, & &1.beat)
    assert beats == [1.0, 2.0, 3.0]
  end

  test "drain clears the buffer" do
    NomosBeam.TxlogBuffer.push(%{path: [:x], value: "v", beat: 0.5})
    NomosBeam.TxlogBuffer.drain()
    assert NomosBeam.TxlogBuffer.drain() == []
  end

  test "peek does not clear the buffer" do
    NomosBeam.TxlogBuffer.push(%{path: [:x], value: "v", beat: 0.5})
    NomosBeam.TxlogBuffer.peek()
    assert NomosBeam.TxlogBuffer.drain() != []
  end

  test "push respects max_entries limit" do
    for i <- 1..250 do
      NomosBeam.TxlogBuffer.push(%{path: [:x], value: i, beat: i * 1.0})
    end

    # Buffer is capped — exact limit is @max_entries = 200 in production.
    # We just verify it doesn't grow unbounded.
    entries = NomosBeam.TxlogBuffer.drain()
    assert length(entries) <= 200
  end
end
