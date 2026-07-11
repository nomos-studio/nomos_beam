# SPDX-FileCopyrightText: 2025-2026 nomos-studio contributors
#
# SPDX-License-Identifier: EPL-2.0

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

  @doc "Notify nous that a supervised service has gone down. Fire-and-forget."
  def service_down(service), do: GenServer.cast(__MODULE__, {:service_down, service})

  @doc "Write a value directly to a ctrl-tree path in nous. Fire-and-forget."
  def ctrl_write(path, value), do: GenServer.cast(__MODULE__, {:ctrl_write, path, value})

  @doc "Ask nous to compute corpus data and write results to ctrl-tree. Fire-and-forget."
  def corpus_query(query), do: GenServer.cast(__MODULE__, {:corpus_query, query})

  @doc "Ask nous to evaluate a Clojure form and write the result to [:repl :last_result]. Fire-and-forget."
  def repl_eval(form), do: GenServer.cast(__MODULE__, {:repl_eval, form})

  @doc "Ask nous to export a corpus work as MusicXML + LilyPond. Fire-and-forget."
  def notation_export_corpus(bwv), do: GenServer.cast(__MODULE__, {:notation_export_corpus, bwv})

  @doc "Ask nous to export session note events in a beat range as MusicXML + LilyPond. Fire-and-forget."
  def notation_export_session(beat_from, beat_to),
    do: GenServer.cast(__MODULE__, {:notation_export_session, beat_from, beat_to})

  @doc "Ask nous to write session LilyPond to disk and compile PDF. Fire-and-forget."
  def notation_save_session, do: GenServer.cast(__MODULE__, :notation_save_session)

  @doc "Signal nous to reconnect to aion at the next bar boundary. Fire-and-forget."
  def aion_reconnect, do: GenServer.cast(__MODULE__, :aion_reconnect)

  @doc "Signal nous to reconnect to kairos at the next bar boundary. Fire-and-forget."
  def kairos_reconnect, do: GenServer.cast(__MODULE__, :kairos_reconnect)

  @doc "Return process health status map for ProcessHealth aggregator."
  def status, do: GenServer.call(__MODULE__, :status)

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
  def handle_call(:status, _from, state) do
    s = if state.connected, do: :up, else: :down
    note = if state.connected, do: to_string(@nous_node), else: nil
    {:reply, %{name: :nous, label: "nous", status: s, note: note}, state}
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

  def handle_cast({:service_down, service}, %{connected: true} = state) do
    :erlang.send({@nous_mbox, @nous_node}, %{op: :service_down, service: service})
    {:noreply, state}
  end

  def handle_cast({:service_down, _service}, state) do
    {:noreply, state}
  end

  def handle_cast({:ctrl_write, path, value}, %{connected: true} = state) do
    :erlang.send({@nous_mbox, @nous_node}, %{op: :ctrl_write, path: path, value: value})
    {:noreply, state}
  end

  def handle_cast({:ctrl_write, _path, _value}, state) do
    {:noreply, state}
  end

  def handle_cast({:corpus_query, query}, %{connected: true} = state) do
    :erlang.send({@nous_mbox, @nous_node}, %{op: :corpus_query, query: query})
    {:noreply, state}
  end

  def handle_cast({:corpus_query, _query}, state) do
    {:noreply, state}
  end

  def handle_cast({:repl_eval, form}, %{connected: true} = state) do
    :erlang.send({@nous_mbox, @nous_node}, %{op: :repl_eval, form: form})
    {:noreply, state}
  end

  def handle_cast({:repl_eval, _form}, state) do
    {:noreply, state}
  end

  def handle_cast({:notation_export_corpus, bwv}, %{connected: true} = state) do
    :erlang.send({@nous_mbox, @nous_node}, %{op: :notation_export_corpus, bwv: bwv})
    {:noreply, state}
  end

  def handle_cast({:notation_export_corpus, _bwv}, state), do: {:noreply, state}

  def handle_cast({:notation_export_session, beat_from, beat_to}, %{connected: true} = state) do
    :erlang.send({@nous_mbox, @nous_node},
                 %{op: :notation_export_session, beat_from: beat_from, beat_to: beat_to})
    {:noreply, state}
  end

  def handle_cast({:notation_export_session, _bf, _bt}, state), do: {:noreply, state}

  def handle_cast(:notation_save_session, %{connected: true} = state) do
    :erlang.send({@nous_mbox, @nous_node}, %{op: :notation_save_session})
    {:noreply, state}
  end

  def handle_cast(:notation_save_session, state), do: {:noreply, state}

  def handle_cast(:aion_reconnect, %{connected: true} = state) do
    :erlang.send({@nous_mbox, @nous_node}, %{op: :aion_reconnect})
    {:noreply, state}
  end

  def handle_cast(:aion_reconnect, state), do: {:noreply, state}

  def handle_cast(:kairos_reconnect, %{connected: true} = state) do
    :erlang.send({@nous_mbox, @nous_node}, %{op: :kairos_reconnect})
    {:noreply, state}
  end

  def handle_cast(:kairos_reconnect, state), do: {:noreply, state}

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

  defp dispatch_echo([:transport | _] = path, value) do
    Phoenix.PubSub.broadcast(NomosBeam.PubSub, "ctrl:transport",
                             {:ctrl_update, path, value})
  end

  defp dispatch_echo([:theory | _] = path, value) do
    Phoenix.PubSub.broadcast(NomosBeam.PubSub, "ctrl:transport",
                             {:ctrl_update, path, value})
  end

  defp dispatch_echo([:corpus | _] = path, value) do
    Phoenix.PubSub.broadcast(NomosBeam.PubSub, "ctrl:corpus",
                             {:ctrl_update, path, value})
  end

  defp dispatch_echo([:session | _] = path, value) do
    Phoenix.PubSub.broadcast(NomosBeam.PubSub, "ctrl:session",
                             {:ctrl_update, path, value})
  end

  defp dispatch_echo([:repl | _] = path, value) do
    Phoenix.PubSub.broadcast(NomosBeam.PubSub, "ctrl:repl",
                             {:ctrl_update, path, value})
  end

  defp dispatch_echo([:notation | _] = path, value) do
    Phoenix.PubSub.broadcast(NomosBeam.PubSub, "ctrl:notation",
                             {:ctrl_update, path, value})
  end

  # Diagnostic echoes land in TxlogBuffer (for the txlog viewer) but need no
  # dedicated PubSub broadcast — the txlog display is the verification surface.
  defp dispatch_echo([:diagnostic | _], _value), do: :ok

  defp dispatch_echo(path, value) do
    Logger.debug("[NousPort] unhandled echo path=#{inspect(path)} value=#{inspect(value)}")
  end
end
