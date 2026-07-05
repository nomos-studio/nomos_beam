# SPDX-FileCopyrightText: 2025-2026 nomos-studio contributors
#
# SPDX-License-Identifier: EPL-2.0

defmodule NomosBeam.KairosSupervisor do
  @moduledoc """
  OTP Port supervisor for the kairos CLAP host.

  Starts kairos as an OS process via an Erlang Port and monitors it;
  on exit, notifies nous via NousPort.service_down(:kairos) then
  restarts after a short delay.  kairos stdout/stderr is forwarded to
  Logger at debug level.

  kairos is started with audio enabled (it drives SurgeXT audio output)
  and bound to its Unix domain socket at /tmp/kairos.sock.

  Configuration via application env:

      config :nomos_beam, NomosBeam.KairosSupervisor,
        enabled:      true,
        kairos_path:  "/usr/local/bin/kairos",
        socket_path:  "/tmp/kairos.sock",
        bpm:          120.0,
        audio_device: 0        # 0 = system default

  By default `enabled` is false — it activates automatically when the
  `NOMOS_STUDIO_SRC` environment variable is set (same convention as
  AionSupervisor and ScSynth).
  """

  use GenServer
  require Logger

  @socket_path "/tmp/kairos.sock"
  @restart_delay 3_000

  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @impl true
  def init(opts) do
    cfg          = Application.get_env(:nomos_beam, __MODULE__, [])
    env_set      = System.get_env("NOMOS_STUDIO_SRC") != nil
    enabled      = Keyword.get(opts, :enabled,      Keyword.get(cfg, :enabled, env_set))
    kairos_path  = Keyword.get(opts, :kairos_path,  Keyword.get(cfg, :kairos_path, default_binary()))
    socket_path  = Keyword.get(opts, :socket_path,  Keyword.get(cfg, :socket_path, @socket_path))
    bpm          = Keyword.get(opts, :bpm,           Keyword.get(cfg, :bpm, 120.0))
    audio_device = Keyword.get(opts, :audio_device,  Keyword.get(cfg, :audio_device, 0))
    if enabled, do: send(self(), :start_kairos)
    {:ok, %{port: nil, enabled: enabled, kairos_path: kairos_path,
            socket_path: socket_path, bpm: bpm, audio_device: audio_device}}
  end

  @impl true
  def handle_info(:start_kairos, state) do
    if File.exists?(state.kairos_path) do
      args = build_args(state)
      Logger.info("[KairosSupervisor] starting #{state.kairos_path} #{Enum.join(args, " ")}")
      port = Port.open({:spawn_executable, state.kairos_path},
                       [:binary, :stderr_to_stdout, :exit_status, args: args])
      {:noreply, %{state | port: port}}
    else
      Logger.warning("[KairosSupervisor] kairos binary not found at #{state.kairos_path} — will retry")
      Process.send_after(self(), :start_kairos, @restart_delay)
      {:noreply, state}
    end
  end

  def handle_info({port, {:data, line}}, %{port: port} = state) do
    Logger.debug("[kairos] #{String.trim(line)}")
    {:noreply, state}
  end

  def handle_info({port, {:exit_status, code}}, %{port: port} = state) do
    Logger.warning("[KairosSupervisor] kairos exited (code #{code}) — notifying nous, restarting in #{@restart_delay}ms")
    NomosBeam.NousPort.service_down(:kairos)
    Process.send_after(self(), :start_kairos, @restart_delay)
    {:noreply, %{state | port: nil}}
  end

  def handle_info(_msg, state), do: {:noreply, state}

  # ── Private ───────────────────────────────────────────────────────────────

  defp build_args(state) do
    ["--socket",       state.socket_path,
     "--bpm",          to_string(state.bpm),
     "--audio-device", to_string(state.audio_device)]
  end

  defp default_binary do
    priv = Path.join([:code.priv_dir(:nomos_beam), "kairos"])

    from_env =
      case System.get_env("NOMOS_STUDIO_SRC") do
        nil -> nil
        src -> Path.join([src, "kairos", "build", "debug", "kairos"])
      end

    cond do
      File.exists?(priv)                    -> priv
      from_env && File.exists?(from_env)    -> from_env
      true                                  -> "kairos"
    end
  end
end
