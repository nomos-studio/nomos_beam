# SPDX-FileCopyrightText: 2025-2026 nomos-studio contributors
#
# SPDX-License-Identifier: EPL-2.0

defmodule NomosBeam.TxlogBuffer do
  @moduledoc """
  In-memory ring buffer for ctrl-tree echo entries received from nous.

  Entries are pushed by NousPort on each ctrl_write_echo and drained by
  DisplayClock at 5 Hz. The buffer holds the last 200 entries;
  older entries are discarded to bound memory use.

  The drain/0 call returns entries in chronological order (oldest first) and
  atomically clears the buffer — DisplayClock broadcasts a complete batch on
  each tick without risk of double-delivery.
  """

  use Agent

  @max_entries 200

  def start_link(_opts), do: Agent.start_link(fn -> [] end, name: __MODULE__)

  @doc "Push a new entry (newest first in storage). Drops oldest beyond @max_entries."
  def push(entry) do
    Agent.update(__MODULE__, fn entries ->
      Enum.take([entry | entries], @max_entries)
    end)
  end

  @doc "Drain all entries, returning them in chronological order. Clears the buffer."
  def drain do
    Agent.get_and_update(__MODULE__, fn entries ->
      {Enum.reverse(entries), []}
    end)
  end

  @doc "Peek at the most recent n entries without clearing. Newest first."
  def peek(n \\ 20) do
    Agent.get(__MODULE__, fn entries -> Enum.take(entries, n) end)
  end
end
