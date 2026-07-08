# SPDX-FileCopyrightText: 2025-2026 nomos-studio contributors
#
# SPDX-License-Identifier: EPL-2.0

defmodule NomosBeam.ProcessHealth do
  @moduledoc """
  Aggregates health status from all supervised processes.

  Called by DisplayClock on each 5 Hz tick and broadcast on
  "nomos:process:health". Each status map has the shape:

      %{name: atom, label: string, status: :up | :down | :disabled, note: string | nil}

  GenServer.call uses a short timeout; any supervisor that doesn't respond
  within 200 ms is reported as :down.
  """

  @services [
    NomosBeam.NousPort,
    NomosBeam.AionSupervisor,
    NomosBeam.ScSynth,
    NomosBeam.KairosSupervisor,
    NomosBeam.M21Supervisor
  ]

  @fallbacks %{
    NomosBeam.NousPort         => %{name: :nous,    label: "nous",    status: :down, note: nil},
    NomosBeam.AionSupervisor   => %{name: :aion,    label: "aion",    status: :down, note: nil},
    NomosBeam.ScSynth          => %{name: :scsynth, label: "scsynth", status: :down, note: nil},
    NomosBeam.KairosSupervisor => %{name: :kairos,  label: "kairos",  status: :down, note: nil},
    NomosBeam.M21Supervisor    => %{name: :m21,     label: "m21",     status: :down, note: nil}
  }

  @doc "Returns a list of status maps, one per supervised process."
  def snapshot do
    Enum.map(@services, fn mod ->
      try do
        GenServer.call(mod, :status, 200)
      catch
        :exit, _ -> Map.fetch!(@fallbacks, mod)
      end
    end)
  end
end
