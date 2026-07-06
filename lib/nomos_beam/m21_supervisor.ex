# SPDX-FileCopyrightText: 2025-2026 nomos-studio contributors
#
# SPDX-License-Identifier: EPL-2.0

defmodule NomosBeam.M21Supervisor do
  @moduledoc """
  OTP Port supervisor for the music21 Python server (m21_server.py).

  Starts m21_server.py in socket mode as an OS process via an Erlang Port
  and monitors it; on exit, notifies nous via NousPort.service_down(:m21)
  then restarts after a short delay.  m21_server.py stdout (ready message +
  any errors) is forwarded to Logger at debug level.

  m21_server.py is started with --socket /tmp/m21.sock.  nous.m21 connects
  to that socket independently (same pattern as nous.kairos / nous.aion).

  Configuration via application env:

      config :nomos_beam, NomosBeam.M21Supervisor,
        enabled:     true,
        python_path: "/Users/me/.venv/music21/bin/python3",
        script_path: "/path/to/nous/script/m21_server.py",
        socket_path: "/tmp/m21.sock"

  By default `enabled` is false — it activates automatically when the
  `NOMOS_STUDIO_SRC` environment variable is set.

  Python is resolved in order:
    1. `python_path` config key
    2. `MUSIC21_PYTHON` env var
    3. `~/.venv/music21/bin/python3` (standard nous venv)
    4. `python3` on PATH

  Script path is resolved in order:
    1. `script_path` config key
    2. `$NOMOS_STUDIO_SRC/nous/script/m21_server.py`
    3. `m21_server.py` on PATH
  """

  use GenServer
  require Logger

  @socket_path "/tmp/m21.sock"
  @restart_delay 3_000

  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @impl true
  def init(opts) do
    cfg         = Application.get_env(:nomos_beam, __MODULE__, [])
    env_set     = System.get_env("NOMOS_STUDIO_SRC") != nil
    enabled     = Keyword.get(opts, :enabled,      Keyword.get(cfg, :enabled, env_set))
    python_path = Keyword.get(opts, :python_path,  Keyword.get(cfg, :python_path, default_python()))
    script_path = Keyword.get(opts, :script_path,  Keyword.get(cfg, :script_path, default_script()))
    socket_path = Keyword.get(opts, :socket_path,  Keyword.get(cfg, :socket_path, @socket_path))
    if enabled, do: send(self(), :start_m21)
    {:ok, %{port: nil, enabled: enabled, python_path: python_path,
            script_path: script_path, socket_path: socket_path}}
  end

  @impl true
  def handle_info(:start_m21, state) do
    cond do
      not File.exists?(state.python_path) ->
        Logger.warning("[M21Supervisor] Python not found at #{state.python_path} — will retry")
        Process.send_after(self(), :start_m21, @restart_delay)
        {:noreply, state}

      not File.exists?(state.script_path) ->
        Logger.warning("[M21Supervisor] m21_server.py not found at #{state.script_path} — will retry")
        Process.send_after(self(), :start_m21, @restart_delay)
        {:noreply, state}

      true ->
        args = [state.script_path, "--socket", state.socket_path]
        Logger.info("[M21Supervisor] starting #{state.python_path} #{Enum.join(args, " ")}")
        port = Port.open({:spawn_executable, state.python_path},
                         [:binary, :stderr_to_stdout, :exit_status, args: args])
        {:noreply, %{state | port: port}}
    end
  end

  def handle_info({port, {:data, line}}, %{port: port} = state) do
    Logger.debug("[m21] #{String.trim(line)}")
    {:noreply, state}
  end

  def handle_info({port, {:exit_status, code}}, %{port: port} = state) do
    Logger.warning("[M21Supervisor] m21_server.py exited (code #{code}) — notifying nous, restarting in #{@restart_delay}ms")
    NomosBeam.NousPort.service_down(:m21)
    Process.send_after(self(), :start_m21, @restart_delay)
    {:noreply, %{state | port: nil}}
  end

  def handle_info(_msg, state), do: {:noreply, state}

  # ── Private ───────────────────────────────────────────────────────────────

  defp default_python do
    venv = Path.expand("~/.venv/music21/bin/python3")
    from_env = System.get_env("MUSIC21_PYTHON")

    cond do
      from_env && File.exists?(from_env) -> from_env
      File.exists?(venv)                 -> venv
      true                               -> "python3"
    end
  end

  defp default_script do
    from_env =
      case System.get_env("NOMOS_STUDIO_SRC") do
        nil -> nil
        src -> Path.join([src, "nous", "script", "m21_server.py"])
      end

    cond do
      from_env && File.exists?(from_env) -> from_env
      true                               -> "m21_server.py"
    end
  end
end
