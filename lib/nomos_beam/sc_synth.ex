# SPDX-FileCopyrightText: 2025-2026 nomos-studio contributors
#
# SPDX-License-Identifier: EPL-2.0

defmodule NomosBeam.ScSynth do
  @moduledoc """
  OTP Port supervisor for sclang (the SuperCollider language process).

  sclang internally boots scsynth and runs the sc-headless.scd boot script,
  which sends /sc-lang-ready to nous's OSC port once scsynth is up.  nous
  registers a persistent /sc-lang-ready handler (sc/watch-sc-ready!) that
  calls connect-sc! on each firing — handling both initial boot and restarts.

  When the sclang Port exits (scsynth crash, SIGTERM, etc.) this supervisor:
    1. Notifies nous via NousPort.service_down(:sc) so it marks SC :stopped
    2. Restarts sclang after @restart_delay ms (OTP-style permanent restart)
    3. sclang sends /sc-lang-ready again, nous reconnects, SynthDefs reload

  ## Configuration

      config :nomos_beam, NomosBeam.ScSynth, enabled: true

  By default `enabled` is `false` — set to `true` explicitly, or it activates
  automatically when the `NOMOS_STUDIO_SRC` environment variable is set.

  The sclang binary is found in order:
    1. `SCLANG_PATH` environment variable
    2. `/Applications/SuperCollider.app/Contents/MacOS/sclang` (macOS .app)
    3. Common PATH locations (Homebrew, system packages)

  The boot script is found at:
    `$NOMOS_STUDIO_SRC/nous/script/sc-headless.scd`
  """

  use GenServer
  require Logger

  @restart_delay 3_000

  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @impl true
  def init(opts) do
    cfg       = Application.get_env(:nomos_beam, __MODULE__, [])
    env_set   = System.get_env("NOMOS_STUDIO_SRC") != nil
    enabled   = Keyword.get(opts, :enabled,     Keyword.get(cfg, :enabled, env_set))
    sc_path   = Keyword.get(opts, :sc_path,     Keyword.get(cfg, :sc_path, default_sclang()))
    boot_script = Keyword.get(opts, :boot_script, Keyword.get(cfg, :boot_script, default_script()))
    if enabled, do: send(self(), :start_sc)
    {:ok, %{port: nil, enabled: enabled, sc_path: sc_path, boot_script: boot_script}}
  end

  @impl true
  def handle_info(:start_sc, state) do
    cond do
      not File.exists?(state.sc_path) ->
        Logger.warning("[ScSynth] sclang not found at #{state.sc_path} — will retry")
        Process.send_after(self(), :start_sc, @restart_delay)
        {:noreply, state}

      not File.exists?(state.boot_script) ->
        Logger.warning("[ScSynth] boot script not found at #{state.boot_script} — will retry")
        Process.send_after(self(), :start_sc, @restart_delay)
        {:noreply, state}

      true ->
        Logger.info("[ScSynth] starting #{state.sc_path} #{state.boot_script}")
        port = Port.open({:spawn_executable, state.sc_path},
                         [:binary, :stderr_to_stdout, :exit_status,
                          args: [state.boot_script]])
        {:noreply, %{state | port: port}}
    end
  end

  def handle_info({port, {:data, line}}, %{port: port} = state) do
    Logger.debug("[sclang] #{String.trim(line)}")
    {:noreply, state}
  end

  def handle_info({port, {:exit_status, code}}, %{port: port} = state) do
    Logger.warning("[ScSynth] sclang exited (code #{code}) — notifying nous, restarting in #{@restart_delay}ms")
    NomosBeam.NousPort.service_down(:sc)
    Process.send_after(self(), :start_sc, @restart_delay)
    {:noreply, %{state | port: nil}}
  end

  def handle_info(_msg, state), do: {:noreply, state}

  # ── Private ───────────────────────────────────────────────────────────────

  defp default_sclang do
    from_env = System.get_env("SCLANG_PATH")
    macos_app = "/Applications/SuperCollider.app/Contents/MacOS/sclang"

    cond do
      from_env && File.exists?(from_env) -> from_env
      File.exists?(macos_app)            -> macos_app
      true                               -> "sclang"
    end
  end

  defp default_script do
    case System.get_env("NOMOS_STUDIO_SRC") do
      nil -> "sc-headless.scd"
      src -> Path.join([src, "nous", "script", "sc-headless.scd"])
    end
  end
end
