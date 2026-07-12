# SPDX-FileCopyrightText: 2025-2026 nomos-studio contributors
#
# SPDX-License-Identifier: EPL-2.0

defmodule NomosBeamWeb.PianoLive do
  use NomosBeamWeb, :live_view

  import NomosBeamWeb.Components.ProcessHealth

  @keyboard_topic   "keyboard:events"
  @display_topic    "nomos:display:frame"
  @transport_topic  "ctrl:transport"
  @health_topic     "nomos:process:health"
  @kb_ctrl_topic    "ctrl:keyboard"
  @max_txlog_entries 50
  @beat_flash_ms 120

  @key_layout [
    %{phys: "a", note: "C",  color: :white, natural: true,  left: 0},
    %{phys: "w", note: "C♯", color: :black, natural: false, left: 28},
    %{phys: "s", note: "D",  color: :white, natural: false, left: 40},
    %{phys: "e", note: "D♯", color: :black, natural: false, left: 68},
    %{phys: "d", note: "E",  color: :white, natural: false, left: 80},
    %{phys: "f", note: "F",  color: :white, natural: false, left: 120},
    %{phys: "t", note: "F♯", color: :black, natural: false, left: 148},
    %{phys: "g", note: "G",  color: :white, natural: false, left: 160},
    %{phys: "y", note: "G♯", color: :black, natural: false, left: 188},
    %{phys: "h", note: "A",  color: :white, natural: false, left: 200},
    %{phys: "u", note: "A♯", color: :black, natural: false, left: 228},
    %{phys: "j", note: "B",  color: :white, natural: false, left: 240}
  ]

  @valid_piano_keys MapSet.new(["a", "w", "s", "e", "d", "f", "t", "g", "y", "h", "u", "j"])

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(NomosBeam.PubSub, @keyboard_topic)
      Phoenix.PubSub.subscribe(NomosBeam.PubSub, @display_topic)
      Phoenix.PubSub.subscribe(NomosBeam.PubSub, @transport_topic)
      Phoenix.PubSub.subscribe(NomosBeam.PubSub, @health_topic)
      Phoenix.PubSub.subscribe(NomosBeam.PubSub, @kb_ctrl_topic)
    end

    {:ok,
     assign(socket,
       pressed: MapSet.new(),
       keys: @key_layout,
       txlog_entries: [],
       bpm: nil,
       beat_n: 0,
       beat_flash: false,
       playing: false,
       theory_key: nil,
       theory_mode: nil,
       health: [],
       health_expanded: false,
       # keyboard mode (M16)
       kb_mode: :pitch,
       interval_position: 1,
       interval_note_name: nil,
       interval_n_steps: 7
     )}
  end

  # ── PubSub / info ─────────────────────────────────────────────────────────

  @impl true
  def handle_info({:keyboard_state, pressed}, socket) do
    {:noreply, assign(socket, pressed: pressed)}
  end

  def handle_info({:display_frame, entries}, socket) do
    updated =
      (socket.assigns.txlog_entries ++ entries)
      |> Enum.take(-@max_txlog_entries)

    {:noreply, assign(socket, txlog_entries: updated)}
  end

  def handle_info({:process_health, health}, socket) do
    {:noreply, assign(socket, health: health)}
  end

  def handle_info({:ctrl_update, [:transport, :bpm], value}, socket) do
    {:noreply, assign(socket, bpm: value)}
  end

  def handle_info({:ctrl_update, [:transport, :playing], value}, socket) do
    {:noreply, assign(socket, playing: value)}
  end

  def handle_info({:ctrl_update, [:transport, :beat_n], value}, socket)
      when value != socket.assigns.beat_n do
    Process.send_after(self(), :clear_beat_flash, @beat_flash_ms)
    {:noreply, assign(socket, beat_n: value, beat_flash: true)}
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

  def handle_info({:ctrl_update, [:keyboard, :mode], value}, socket) do
    {:noreply, assign(socket, kb_mode: value)}
  end

  def handle_info({:ctrl_update, [:keyboard, :interval_position], value}, socket) do
    {:noreply, assign(socket, interval_position: value)}
  end

  def handle_info({:ctrl_update, [:keyboard, :interval_note_name], value}, socket) do
    {:noreply, assign(socket, interval_note_name: value)}
  end

  def handle_info({:ctrl_update, _path, _value}, socket) do
    {:noreply, socket}
  end

  # ── Keyboard events ───────────────────────────────────────────────────────

  @impl true
  def handle_event("piano_keydown", %{"key" => key, "repeat" => true}, socket) do
    # Suppress browser key-repeat — we only want the initial press.
    _ = key
    {:noreply, socket}
  end

  def handle_event("piano_keydown", %{"key" => key}, socket) do
    if MapSet.member?(@valid_piano_keys, key) do
      NomosBeam.NousPort.key_down(key)
      {:noreply, assign(socket, pressed: MapSet.put(socket.assigns.pressed, key))}
    else
      {:noreply, socket}
    end
  end

  def handle_event("piano_keydown", _params, socket), do: {:noreply, socket}

  def handle_event("piano_keyup", %{"key" => key}, socket) do
    if MapSet.member?(@valid_piano_keys, key) do
      NomosBeam.NousPort.key_up(key)
      {:noreply, assign(socket, pressed: MapSet.delete(socket.assigns.pressed, key))}
    else
      {:noreply, socket}
    end
  end

  def handle_event("piano_keyup", _params, socket), do: {:noreply, socket}

  # ── Health panel ──────────────────────────────────────────────────────────

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
    ~H"""
    <div class="flex flex-col items-center gap-10 p-10 min-h-screen"
         phx-window-keydown="piano_keydown"
         phx-window-keyup="piano_keyup">

      <%!-- Status strip — BPM, beat flash, key/mode, nav, health --%>
      <div class="w-full max-w-2xl flex items-center gap-5 px-4 py-2 bg-base-200 rounded font-mono text-xs tracking-widest">
        <span class="text-base-content/60 uppercase">bpm</span>
        <span class="text-primary tabular-nums w-14">
          {format_bpm(@bpm)}
        </span>
        <span class={[
          "w-2 h-2 rounded-full transition-colors",
          if(@beat_flash, do: "bg-primary", else: "bg-base-content/30")
        ]}>
        </span>
        <span :if={@theory_key} class="ml-3 text-base-content/60 uppercase">key</span>
        <span :if={@theory_key} class="text-accent">{@theory_key}</span>
        <span :if={@theory_mode} class="text-accent/80">{@theory_mode}</span>
        <span :if={!@playing && @bpm == nil} class="text-base-content/45 italic">
          waiting for kairos…
        </span>
        <a href="/corpus" class="ml-auto text-base-content/55 hover:text-base-content/85 text-xs font-mono tracking-widest">corpus</a>
        <a href="/repl" class="text-base-content/55 hover:text-base-content/85 text-xs font-mono tracking-widest">repl</a>
        <a href="/notation" class="text-base-content/55 hover:text-base-content/85 text-xs font-mono tracking-widest">notation</a>
        <a href="/sequencer" class="text-base-content/55 hover:text-base-content/85 text-xs font-mono tracking-widest">seq</a>
        <.process_health health={@health} expanded={@health_expanded} />
      </div>

      <header class="font-mono tracking-widest text-base-content/70 text-sm uppercase">
        nomos-studio
      </header>

      <%!-- Mode badge --%>
      <div class="font-mono text-xs tracking-widest uppercase flex items-center gap-3">
        <span class="text-base-content/45">mode</span>
        <span class={[
          "px-2 py-0.5 rounded text-xs",
          case @kb_mode do
            :pitch              -> "bg-primary/20 text-primary"
            :interval           -> "bg-accent/20 text-accent"
            :interval_last_note -> "bg-secondary/20 text-secondary"
            _                   -> "bg-base-300 text-base-content/60"
          end
        ]}>
          {kb_mode_label(@kb_mode)}
        </span>
        <span class="text-base-content/30 text-[10px]">
          (ctrl/write! [:keyboard :mode] :interval)
        </span>
      </div>

      <%!-- Keyboard display — piano in :pitch mode, solfege wheel in interval modes --%>
      <%= if @kb_mode in [:interval, :interval_last_note] do %>
        <%!-- Solfege wheel --%>
        <div class="flex flex-col items-center gap-2">
          <svg width="220" height="220" viewBox="-110 -110 220 220" class="block">
            {solfege_wheel_svg(@interval_position, @interval_n_steps, @interval_note_name)}
          </svg>
          <p class="font-mono text-xs text-base-content/55 tracking-widest">
            a/s ±1 · d/f ±2 · g/h ±3 · j/w ±4
          </p>
        </div>
      <% else %>
        <%!-- Piano keyboard (pitch mode) --%>
        <div class="piano" style="position: relative; width: 280px; height: 150px;">
          <div
            :for={key <- @keys}
            class={[
              "piano-key",
              to_string(key.color),
              key.natural && "c-natural",
              MapSet.member?(@pressed, key.phys) && "pressed"
            ]}
            style={"left: #{key.left}px"}
            title={key.note}
          >
            <span class="piano-key-label">{key.phys}</span>
          </div>
        </div>
        <p class="font-mono text-xs text-base-content/55 tracking-widest">
          a · s · d · f · g · h · j &nbsp;→&nbsp; C D E F G A B
        </p>
      <% end %>

      <%!-- Txlog viewer --%>
      <div class="w-full max-w-2xl">
        <h2 class="font-mono text-xs text-base-content/60 tracking-widest uppercase mb-2">
          ctrl-tree txlog
        </h2>
        <div class="font-mono text-xs bg-base-200 rounded p-3 h-48 overflow-y-auto">
          <table class="w-full border-collapse">
            <thead>
              <tr class="text-base-content/60">
                <th class="text-left pr-4 pb-1 font-normal w-16">beat</th>
                <th class="text-left pr-4 pb-1 font-normal">path</th>
                <th class="text-left font-normal">value</th>
              </tr>
            </thead>
            <tbody>
              <tr :for={entry <- @txlog_entries} class="text-base-content/85">
                <td class="pr-4 tabular-nums">
                  {format_beat(entry[:beat])}
                </td>
                <td class="pr-4 text-primary">
                  {format_path(entry[:path])}
                </td>
                <td class="text-accent">
                  {inspect(entry[:value])}
                </td>
              </tr>
            </tbody>
          </table>
          <p :if={@txlog_entries == []} class="text-base-content/45 italic">
            waiting for ctrl-tree events…
          </p>
        </div>
      </div>
    </div>
    """
  end

  defp format_bpm(nil), do: "—"
  defp format_bpm(bpm) when is_float(bpm), do: :erlang.float_to_binary(bpm, decimals: 1)
  defp format_bpm(bpm), do: to_string(bpm)

  defp format_beat(nil), do: "—"
  defp format_beat(beat) when is_float(beat), do: :erlang.float_to_binary(beat, decimals: 2)
  defp format_beat(beat), do: to_string(beat)

  defp format_path(nil), do: "—"

  defp format_path(path) when is_list(path) do
    inner = path |> Enum.map_join(" ", &":#{&1}")
    "[#{inner}]"
  end

  defp format_path(path), do: inspect(path)

  # ── Keyboard mode helpers ─────────────────────────────────────────────────

  defp kb_mode_label(:pitch),              do: "pitch"
  defp kb_mode_label(:interval),           do: "interval"
  defp kb_mode_label(:interval_last_note), do: "interval (last note)"
  defp kb_mode_label(other),               do: to_string(other)

  # Render the solfege wheel as an SVG fragment (safe HTML string).
  # pos      — 1-indexed current scale degree (integer)
  # n_steps  — total scale steps (integer)
  # note_name — note-class string or nil
  defp solfege_wheel_svg(pos, n_steps, note_name) do
    r_outer = 85
    r_inner = 52
    r_dot   = 7
    r_label = 68
    solfege = ["Do", "Re", "Mi", "Fa", "Sol", "La", "Ti"]

    step_angle = 2 * :math.pi() / n_steps

    dots =
      Enum.map(0..(n_steps - 1), fn i ->
        angle   = i * step_angle - :math.pi() / 2
        lx      = r_label * :math.cos(angle)
        ly      = r_label * :math.sin(angle)
        sol_lbl = Enum.at(solfege, rem(i, 7))
        active  = i + 1 == pos

        dot_fill   = if active, do: "#ffffff", else: "rgba(255,255,255,0.25)"
        label_fill = if active, do: "#ffffff", else: "rgba(255,255,255,0.45)"

        """
        <circle cx="#{format_f(lx)}" cy="#{format_f(ly)}" r="#{r_dot}"
                fill="#{dot_fill}" />
        <text x="#{format_f(lx)}" y="#{format_f(ly + r_dot + 9)}"
              text-anchor="middle" font-family="monospace" font-size="9"
              fill="#{label_fill}">#{sol_lbl}</text>
        """
      end)
      |> Enum.join()

    centre_text =
      if note_name do
        """
        <text x="0" y="6" text-anchor="middle"
              font-family="monospace" font-size="22" font-weight="bold"
              fill="rgba(255,255,255,0.9)">#{note_name}</text>
        <text x="0" y="24" text-anchor="middle"
              font-family="monospace" font-size="11"
              fill="rgba(255,255,255,0.45)">deg #{pos}</text>
        """
      else
        """
        <text x="0" y="8" text-anchor="middle"
              font-family="monospace" font-size="13"
              fill="rgba(255,255,255,0.35)">deg #{pos}</text>
        """
      end

    """
    <circle cx="0" cy="0" r="#{r_outer}" fill="rgba(255,255,255,0.04)"
            stroke="rgba(255,255,255,0.12)" stroke-width="1" />
    <circle cx="0" cy="0" r="#{r_inner}" fill="rgba(0,0,0,0.35)" />
    #{dots}
    #{centre_text}
    """
  end

  defp format_f(f), do: :erlang.float_to_binary(f, decimals: 2)
end
