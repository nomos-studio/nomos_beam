defmodule NomosBeam.NousPort do
  @moduledoc """
  GenServer that owns the Erlang distribution connection to the nous JVM peer.

  Starts BEAM distribution (longnames, @localhost) if not already running and
  attempts to connect to `nous@localhost` on startup, retrying every 2 s until
  successful.

  Keyboard events arrive via `key_down/1` and `key_up/1` casts. When nous is
  connected, events are forwarded as `ctrl_write` messages to the `ctrl`
  mailbox on `nous@localhost`. The nous ctrl-tree writes the value and the
  BeamMount echoes it back as a `ctrl_write_echo` message to this GenServer's
  registered name (`Elixir.NomosBeam.NousPort`); the echo drives `KeyboardServer`
  — completing the causal chain.

  When nous is not connected, keyboard events are dropped silently.
  """

  use GenServer
  require Logger

  @nous_node :"nous@127.0.0.1"
  @nous_mbox :ctrl
  @connect_interval 2_000
  @cookie :nomos_studio_dev

  # ── Public API ────────────────────────────────────────────────────────────

  def start_link(_opts), do: GenServer.start_link(__MODULE__, [], name: __MODULE__)

  @doc "Route a key-down event through the ctrl-tree. Fire-and-forget."
  def key_down(key), do: GenServer.cast(__MODULE__, {:key_event, :key_down, key})

  @doc "Route a key-up event through the ctrl-tree. Fire-and-forget."
  def key_up(key), do: GenServer.cast(__MODULE__, {:key_event, :key_up, key})

  # ── GenServer callbacks ───────────────────────────────────────────────────

  @impl true
  def init(_opts) do
    send(self(), :try_connect)
    {:ok, %{connected: false}}
  end

  @impl true
  def handle_info(:try_connect, state) do
    with :ok <- ensure_distributed(),
         true <- Node.connect(@nous_node) do
      :erlang.monitor_node(@nous_node, true)
      Logger.info("[NousPort] connected to #{@nous_node}")
      {:noreply, %{state | connected: true}}
    else
      _ ->
        Process.send_after(self(), :try_connect, @connect_interval)
        {:noreply, state}
    end
  end

  # Echo received from BeamMount after a ctrl-tree write in nous.
  # Includes beat/wall_ns/source for the txlog display pipeline.
  def handle_info(%{op: :ctrl_write_echo, path: path, value: value} = echo, state) do
    dispatch_echo(path, value)
    NomosBeam.TxlogBuffer.push(Map.take(echo, [:path, :value, :beat, :wall_ns, :source]))
    {:noreply, state}
  end

  # BEAM nodedown notification — mark as disconnected and retry.
  def handle_info({:nodedown, @nous_node}, state) do
    Logger.info("[NousPort] nous@localhost went down — will retry")
    Process.send_after(self(), :try_connect, @connect_interval)
    {:noreply, %{state | connected: false}}
  end

  def handle_info(msg, state) do
    Logger.debug("[NousPort] unexpected message: #{inspect(msg)}")
    {:noreply, state}
  end

  @impl true
  def handle_cast({:key_event, op, key}, %{connected: true} = state)
      when op in [:key_down, :key_up] do
    :erlang.send({@nous_mbox, @nous_node}, %{op: :ctrl_write, path: [:input, :keyboard, op], value: key})
    {:noreply, state}
  end

  def handle_cast({:key_event, _op, _key}, state) do
    # nous not connected — drop silently
    {:noreply, state}
  end

  # ── Private helpers ───────────────────────────────────────────────────────

  defp ensure_distributed do
    if Node.alive?() do
      :ok
    else
      case Node.start(:"nomos_beam@127.0.0.1", :longnames) do
        {:ok, _} ->
          :erlang.set_cookie(node(), @cookie)
          Logger.info("[NousPort] distribution started as #{node()}")
          :ok

        {:error, reason} ->
          Logger.debug("[NousPort] distribution not yet available: #{inspect(reason)}")
          :error
      end
    end
  end

  defp dispatch_echo([:input, :keyboard, :key_down], value) do
    NomosBeam.KeyboardServer.key_down(value)
  end

  defp dispatch_echo([:input, :keyboard, :key_up], value) do
    NomosBeam.KeyboardServer.key_up(value)
  end

  defp dispatch_echo(path, value) do
    Logger.debug("[NousPort] unhandled echo path=#{inspect(path)} value=#{inspect(value)}")
  end
end
