# SPDX-FileCopyrightText: 2025-2026 nomos-studio contributors
#
# SPDX-License-Identifier: EPL-2.0

defmodule NomosBeamWeb.SequencerLive do
  @moduledoc """
  Step sequencer + piano roll LiveView (M15).

  Shows:
  - 16-step degree grid: displays the active pattern from [:seq :name :steps]
    in the ctrl-tree; active step highlighted as the sequencer runs.
  - Piano roll: scrolling note-event display from nous.core/play! telemetry
    (nomos:seq:note PubSub topic).
  - Transport strip (BPM, beat indicator, key/mode).
  - ProcessHealth expando-matter.

  Pattern editing is REPL-driven for M15. The BEAM view is read-only.
  """

  use NomosBeamWeb, :live_view

  import NomosBeamWeb.Components.ProcessHealth

  @seq_topic       "ctrl:seq"
  @note_topic      "nomos:seq:note"
  @display_topic   "nomos:display:frame"
  @transport_topic "ctrl:transport"
  @health_topic    "nomos:process:health"

  # Rolling piano roll — keep last N note events.
  @max_notes 128

  # Piano roll display range: MIDI C2 (36) to B5 (83) — 4 octaves + minor sixth.
  @pitch_lo 36
  @pitch_hi 83
  @pitch_range (@pitch_hi - @pitch_lo + 1)

  # SVG geometry constants (pixels).
  @roll_px_per_beat 48
  @roll_beat_window 16
  @roll_width  (@roll_px_per_beat * @roll_beat_window)
  @roll_row_h  5
  @roll_height (@pitch_range * @roll_row_h)
  @piano_strip_w 24

  # ── Mount ─────────────────────────────────────────────────────────────────

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(NomosBeam.PubSub, @seq_topic)
      Phoenix.PubSub.subscribe(NomosBeam.PubSub, @note_topic)
      Phoenix.PubSub.subscribe(NomosBeam.PubSub, @display_topic)
      Phoenix.PubSub.subscribe(NomosBeam.PubSub, @transport_topic)
      Phoenix.PubSub.subscribe(NomosBeam.PubSub, @health_topic)
    end

    {:ok,
     assign(socket,
       # seq state
       seq_steps:      default_steps(),
       seq_active_idx: nil,
       seq_name:       nil,
       seq_running:    false,
       # note events for piano roll (newest last)
       notes:          [],
       roll_beat:      0.0,
       # transport
       bpm:            nil,
       beat_n:         0,
       beat_flash:     false,
       theory_key:     nil,
       theory_mode:    nil,
       # health
       health:         [],
       health_expanded: false
     )}
  end

  # ── PubSub / info ─────────────────────────────────────────────────────────

  @impl true
  def handle_info({:note_event, ev}, socket) do
    note = %{
      pitch: ev[:pitch] || ev.pitch,
      vel:   ev[:vel]   || ev.vel,
      beat:  ev[:beat]  || ev.beat,
      dur:   ev[:dur]   || ev.dur
    }
    notes =
      (socket.assigns.notes ++ [note])
      |> Enum.take(-@max_notes)
    # Advance the roll cursor to the latest note beat.
    roll_beat = max(socket.assigns.roll_beat, note.beat)
    {:noreply, assign(socket, notes: notes, roll_beat: roll_beat)}
  end

  def handle_info({:display_frame, _entries}, socket) do
    # TxlogBuffer entries not directly used here; transport events arrive
    # via ctrl:transport subscriptions.
    {:noreply, socket}
  end

  def handle_info({:process_health, health}, socket) do
    {:noreply, assign(socket, health: health)}
  end

  def handle_info({:ctrl_update, [:transport, :bpm], value}, socket) do
    {:noreply, assign(socket, bpm: value)}
  end

  def handle_info({:ctrl_update, [:transport, :playing], value}, socket) do
    {:noreply, assign(socket, seq_running: value)}
  end

  def handle_info({:ctrl_update, [:transport, :beat_n], value}, socket)
      when value != socket.assigns.beat_n do
    Process.send_after(self(), :clear_beat_flash, 120)
    {:noreply, assign(socket, beat_n: value, beat_flash: true, roll_beat: value * 1.0)}
  end

  def handle_info({:ctrl_update, [:transport, :beat_n], _value}, socket) do
    {:noreply, socket}
  end

  def handle_info(:clear_beat_flash, socket) do
    {:noreply, assign(socket, beat_flash: false)}
  end

  def handle_info({:ctrl_update, [:theory, :key], value}, socket) do
    {:noreply, assign(socket, theory_key: value)}
  end

  def handle_info({:ctrl_update, [:theory, :mode], value}, socket) do
    {:noreply, assign(socket, theory_mode: value)}
  end

  # Seq ctrl-tree echoes: [:seq :name :steps], [:seq :name :active_idx], etc.
  def handle_info({:ctrl_update, [:seq, _name, :steps], steps}, socket) do
    {:noreply, assign(socket, seq_steps: coerce_steps(steps))}
  end

  def handle_info({:ctrl_update, [:seq, name, :active_idx], idx}, socket) do
    {:noreply, assign(socket, seq_active_idx: idx, seq_name: name)}
  end

  def handle_info({:ctrl_update, [:seq, _name, :running], value}, socket) do
    {:noreply, assign(socket, seq_running: value)}
  end

  def handle_info({:ctrl_update, _path, _value}, socket) do
    {:noreply, socket}
  end

  # ── Events ────────────────────────────────────────────────────────────────

  @impl true
  def handle_event("toggle_health", _params, socket) do
    {:noreply, assign(socket, health_expanded: !socket.assigns.health_expanded)}
  end

  def handle_event("health_keydown", %{"key" => "Escape"}, socket) do
    {:noreply, assign(socket, health_expanded: false)}
  end

  def handle_event("health_keydown", _params, socket) do
    {:noreply, socket}
  end

  # ── Render ────────────────────────────────────────────────────────────────

  @impl true
  def render(assigns) do
    assigns =
      assigns
      |> assign(:roll_width,       @roll_width)
      |> assign(:roll_height,      @roll_height)
      |> assign(:piano_strip_w,    @piano_strip_w)
      |> assign(:pitch_lo,         @pitch_lo)
      |> assign(:pitch_hi,         @pitch_hi)
      |> assign(:pitch_range,      @pitch_range)
      |> assign(:roll_row_h,       @roll_row_h)
      |> assign(:roll_px_per_beat, @roll_px_per_beat)
      |> assign(:roll_beat_window, @roll_beat_window)

    ~H"""
    <div class="flex flex-col items-center gap-6 p-8 min-h-screen">

      <%!-- Status strip --%>
      <div class="w-full max-w-4xl flex items-center gap-5 px-4 py-2 bg-base-200 rounded font-mono text-xs tracking-widest">
        <span class="text-base-content/60 uppercase">bpm</span>
        <span class="text-primary tabular-nums w-14">{format_bpm(@bpm)}</span>
        <span class={[
          "w-2 h-2 rounded-full transition-colors",
          if(@beat_flash, do: "bg-primary", else: "bg-base-content/30")
        ]}>
        </span>
        <span :if={@theory_key} class="ml-3 text-base-content/60 uppercase">key</span>
        <span :if={@theory_key} class="text-accent">{@theory_key}</span>
        <span :if={@theory_mode} class="text-accent/80">{@theory_mode}</span>
        <span :if={@seq_running} class="ml-3 w-2 h-2 rounded-full bg-success animate-pulse"></span>
        <span :if={@seq_running} class="text-success text-xs">running</span>
        <a href="/" class="ml-auto text-base-content/55 hover:text-base-content/85 text-xs font-mono">piano</a>
        <a href="/corpus" class="text-base-content/55 hover:text-base-content/85 text-xs font-mono">corpus</a>
        <a href="/repl" class="text-base-content/55 hover:text-base-content/85 text-xs font-mono">repl</a>
        <a href="/notation" class="text-base-content/55 hover:text-base-content/85 text-xs font-mono">notation</a>
        <.process_health health={@health} expanded={@health_expanded} />
      </div>

      <header class="font-mono tracking-widest text-base-content/70 text-sm uppercase">
        sequencer
      </header>

      <%!-- Step grid — 16 steps × degree/rest display --%>
      <div class="w-full max-w-4xl">
        <h2 class="font-mono text-xs text-base-content/60 tracking-widest uppercase mb-2">
          pattern
          <span :if={@seq_name} class="text-primary ml-2">{inspect(@seq_name)}</span>
        </h2>
        <div class="grid gap-1" style="grid-template-columns: repeat(16, minmax(0, 1fr))">
          <div
            :for={{step, idx} <- Enum.with_index(@seq_steps)}
            class={[
              "flex flex-col items-center justify-center rounded p-1",
              "font-mono text-xs border border-base-content/20",
              "min-w-0 aspect-square",
              if(@seq_active_idx == idx,
                do:   "bg-primary/30 border-primary text-primary",
                else: "bg-base-200 text-base-content/75")
            ]}
          >
            <span class="text-sm leading-none tabular-nums">
              {degree_label(step)}
            </span>
            <span class="text-base-content/40 text-[9px] leading-none mt-0.5">
              {vel_label(step)}
            </span>
          </div>
        </div>
        <p class="font-mono text-xs text-base-content/35 mt-2">
          edit pattern with (ctrl/write! [:seq :&lt;name&gt; :steps] steps) in REPL
        </p>
      </div>

      <%!-- Piano roll — SVG --%>
      <div class="w-full max-w-4xl">
        <h2 class="font-mono text-xs text-base-content/60 tracking-widest uppercase mb-2">
          piano roll
        </h2>
        <div class="bg-base-200 rounded overflow-hidden" style={"height: #{@roll_height + 2}px"}>
          <svg
            width={@piano_strip_w + @roll_width}
            height={@roll_height}
            class="block"
            style="overflow: visible"
          >
            <%!-- Keyboard strip (left) --%>
            <g transform={"translate(0,0)"}>
              <%= for midi <- @pitch_lo..@pitch_hi do %>
                <rect
                  x={0}
                  y={pitch_to_y(midi, assigns)}
                  width={@piano_strip_w - 1}
                  height={@roll_row_h - 1}
                  fill={if white_key?(midi), do: "#f5f5f5", else: "#222"}
                  rx="1"
                />
              <% end %>
            </g>

            <%!-- Note grid (right of keyboard strip) --%>
            <g transform={"translate(#{@piano_strip_w},0)"}>
              <%!-- Beat grid lines --%>
              <%= for b <- 0..@roll_beat_window do %>
                <line
                  x1={b * @roll_px_per_beat}
                  y1={0}
                  x2={b * @roll_px_per_beat}
                  y2={@roll_height}
                  stroke="rgba(255,255,255,0.05)"
                  stroke-width="1"
                />
              <% end %>

              <%!-- Pitch lane alternating background --%>
              <%= for midi <- @pitch_lo..@pitch_hi do %>
                <rect
                  x={0}
                  y={pitch_to_y(midi, assigns)}
                  width={@roll_width}
                  height={@roll_row_h}
                  fill={if black_key?(midi), do: "rgba(0,0,0,0.2)", else: "transparent"}
                />
              <% end %>

              <%!-- Note blocks --%>
              <%= for note <- visible_notes(@notes, @roll_beat, assigns) do %>
                <rect
                  x={note_x(note, @roll_beat, assigns)}
                  y={pitch_to_y(note.pitch, assigns)}
                  width={max(2, note.dur * @roll_px_per_beat - 1)}
                  height={@roll_row_h - 1}
                  fill={note_color(note.vel)}
                  rx="1"
                  opacity="0.9"
                />
              <% end %>

              <%!-- Current beat cursor line --%>
              <line
                x1={@roll_width}
                y1={0}
                x2={@roll_width}
                y2={@roll_height}
                stroke="rgba(255,100,100,0.7)"
                stroke-width="1"
              />
            </g>
          </svg>
        </div>
        <p :if={@notes == []} class="font-mono text-xs text-base-content/35 mt-1 italic">
          waiting for note events…
        </p>
      </div>

    </div>
    """
  end

  # ── Private helpers ───────────────────────────────────────────────────────

  defp default_steps do
    Enum.map(1..16, fn i ->
      %{degree: if(rem(i, 4) == 0, do: nil, else: rem(i - 1, 7) + 1), vel: 100, gate: 0.9}
    end)
  end

  defp coerce_steps(steps) when is_list(steps) do
    Enum.map(steps, fn s ->
      s = if is_map(s), do: s, else: %{}
      %{
        degree: s[:degree] || s["degree"],
        vel:    s[:vel]    || s["vel"]    || 100,
        gate:   s[:gate]   || s["gate"]   || 0.9
      }
    end)
  end

  defp coerce_steps(_), do: default_steps()

  defp degree_label(%{degree: nil}),    do: "—"
  defp degree_label(%{degree: :rest}),  do: "—"
  defp degree_label(%{degree: d}) when is_integer(d), do: to_string(d)
  defp degree_label(_),                 do: "?"

  defp vel_label(%{vel: v}) when is_integer(v), do: "v#{v}"
  defp vel_label(_), do: ""

  defp pitch_to_y(midi, %{pitch_hi: hi, roll_row_h: row_h}) do
    (hi - midi) * row_h
  end

  defp white_key?(midi) do
    rem(midi, 12) not in [1, 3, 6, 8, 10]
  end

  defp black_key?(midi), do: not white_key?(midi)

  defp note_x(note, roll_beat, %{roll_width: _w, roll_px_per_beat: ppb, roll_beat_window: bw}) do
    # Align so that roll_beat maps to the right edge (x = w).
    offset = (note.beat - (roll_beat - bw)) * ppb
    max(0, offset)
  end

  defp visible_notes(notes, roll_beat, %{roll_beat_window: bw}) do
    lo = roll_beat - bw
    Enum.filter(notes, fn n -> n.beat >= lo && n.beat <= roll_beat end)
  end

  defp note_color(vel) when is_number(vel) do
    # Map velocity 0–127 to a warm amber hue with brightness.
    brightness = trunc(80 + (vel / 127 * 80))
    "hsl(38,90%,#{brightness}%)"
  end

  defp note_color(_), do: "hsl(38,90%,80%)"

  defp format_bpm(nil), do: "—"
  defp format_bpm(bpm) when is_float(bpm), do: :erlang.float_to_binary(bpm, decimals: 1)
  defp format_bpm(bpm), do: to_string(bpm)
end
