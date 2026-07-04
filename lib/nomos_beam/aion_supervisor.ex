# SPDX-FileCopyrightText: 2025-2026 nomos-studio contributors
#
# SPDX-License-Identifier: EPL-2.0

defmodule NomosBeam.AionSupervisor do
  @moduledoc """
  OTP Port supervisor for the aion C++ session substrate.

  Starts aion as an OS process via an Erlang Port and monitors it;
  on exit, restarts after a short delay. aion's stdout/stderr is
  forwarded to Logger at debug level.

  MIDI port is configured via application config:
    config :nomos_beam, NomosBeam.AionSupervisor, midi_port: 0

  Set midi_port to -1 (the default) to start aion without opening a
  MIDI output port — useful to confirm the socket path and see available
  ports in the log before committing to an index.

  The Unix socket path defaults to /tmp/aion.sock, matching the aion
  default and nous.aion/start!.
  """

  use GenServer
  require Logger

  @socket_path "/tmp/aion.sock"
  @restart_delay 2_000

  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @impl true
  def init(opts) do
    cfg = Application.get_env(:nomos_beam, __MODULE__, [])
    env_set   = System.get_env("NOMOS_STUDIO_SRC") != nil
    enabled   = Keyword.get(opts, :enabled,    Keyword.get(cfg, :enabled, env_set))
    midi_port = Keyword.get(opts, :midi_port,  Keyword.get(cfg, :midi_port, -1))
    aion_path = Keyword.get(opts, :aion_path,  Keyword.get(cfg, :aion_path, default_binary()))
    if enabled, do: send(self(), :start_aion)
    {:ok, %{port: nil, enabled: enabled, midi_port: midi_port, aion_path: aion_path}}
  end

  @impl true
  def handle_info(:start_aion, state) do
    if File.exists?(state.aion_path) do
      args = build_args(state.midi_port)
      Logger.info("[AionSupervisor] starting #{state.aion_path} #{Enum.join(args, " ")}")
      port = Port.open({:spawn_executable, state.aion_path},
                       [:binary, :stderr_to_stdout, :exit_status, args: args])
      {:noreply, %{state | port: port}}
    else
      Logger.warning("[AionSupervisor] aion binary not found at #{state.aion_path} — will retry")
      Process.send_after(self(), :start_aion, @restart_delay)
      {:noreply, state}
    end
  end

  def handle_info({port, {:data, line}}, %{port: port} = state) do
    Logger.debug("[aion] #{String.trim(line)}")
    {:noreply, state}
  end

  def handle_info({port, {:exit_status, code}}, %{port: port} = state) do
    Logger.warning("[AionSupervisor] aion exited (code #{code}) — restarting in #{@restart_delay}ms")
    Process.send_after(self(), :start_aion, @restart_delay)
    {:noreply, %{state | port: nil}}
  end

  def handle_info(_msg, state), do: {:noreply, state}

  # ── Private ───────────────────────────────────────────────────────────────

  defp build_args(midi_port) do
    base = ["--no-audio", "--socket", @socket_path]
    if midi_port >= 0, do: base ++ ["--midi-port", to_string(midi_port)], else: base
  end

  defp default_binary do
    priv = Path.join([:code.priv_dir(:nomos_beam), "aion"])

    from_env =
      case System.get_env("NOMOS_STUDIO_SRC") do
        nil -> nil
        src -> Path.join([src, "aion", "build", "debug", "aion"])
      end

    cond do
      File.exists?(priv)                    -> priv
      from_env && File.exists?(from_env)    -> from_env
      true                                  -> "aion"
    end
  end
end
