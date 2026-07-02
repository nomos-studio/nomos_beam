defmodule NomosBeamWeb.PianoLive do
  use NomosBeamWeb, :live_view

  @keyboard_topic "keyboard:events"
  @display_topic  "nomos:display:frame"
  @max_txlog_entries 50

  @key_layout [
    %{phys: "a", note: "C", color: :white, natural: true, left: 0},
    %{phys: "w", note: "C♯", color: :black, natural: false, left: 28},
    %{phys: "s", note: "D", color: :white, natural: false, left: 40},
    %{phys: "e", note: "D♯", color: :black, natural: false, left: 68},
    %{phys: "d", note: "E", color: :white, natural: false, left: 80},
    %{phys: "f", note: "F", color: :white, natural: false, left: 120},
    %{phys: "t", note: "F♯", color: :black, natural: false, left: 148},
    %{phys: "g", note: "G", color: :white, natural: false, left: 160},
    %{phys: "y", note: "G♯", color: :black, natural: false, left: 188},
    %{phys: "h", note: "A", color: :white, natural: false, left: 200},
    %{phys: "u", note: "A♯", color: :black, natural: false, left: 228},
    %{phys: "j", note: "B", color: :white, natural: false, left: 240}
  ]

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(NomosBeam.PubSub, @keyboard_topic)
      Phoenix.PubSub.subscribe(NomosBeam.PubSub, @display_topic)
    end

    {:ok,
     assign(socket,
       pressed: MapSet.new(),
       keys: @key_layout,
       txlog_entries: []
     )}
  end

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

  @impl true
  def render(assigns) do
    ~H"""
    <div class="flex flex-col items-center gap-10 p-10 min-h-screen">
      <header class="font-mono tracking-widest text-base-content/50 text-sm uppercase">
        nomos-studio
      </header>

      <%!-- Piano keyboard panel --%>
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

      <p class="font-mono text-xs text-base-content/30 tracking-widest">
        a · s · d · f · g · h · j &nbsp;→&nbsp; C D E F G A B
      </p>

      <%!-- Txlog viewer panel --%>
      <div class="w-full max-w-2xl">
        <h2 class="font-mono text-xs text-base-content/40 tracking-widest uppercase mb-2">
          ctrl-tree txlog
        </h2>
        <div class="font-mono text-xs bg-base-200 rounded p-3 h-48 overflow-y-auto">
          <table class="w-full border-collapse">
            <thead>
              <tr class="text-base-content/40">
                <th class="text-left pr-4 pb-1 font-normal w-16">beat</th>
                <th class="text-left pr-4 pb-1 font-normal">path</th>
                <th class="text-left font-normal">value</th>
              </tr>
            </thead>
            <tbody>
              <tr :for={entry <- @txlog_entries} class="text-base-content/70">
                <td class="pr-4 tabular-nums">
                  {format_beat(entry[:beat])}
                </td>
                <td class="pr-4 text-primary/80">
                  {format_path(entry[:path])}
                </td>
                <td class="text-accent/80">
                  {inspect(entry[:value])}
                </td>
              </tr>
            </tbody>
          </table>
          <p :if={@txlog_entries == []} class="text-base-content/20 italic">
            waiting for ctrl-tree events…
          </p>
        </div>
      </div>
    </div>
    """
  end

  defp format_beat(nil), do: "—"
  defp format_beat(beat) when is_float(beat), do: :erlang.float_to_binary(beat, decimals: 2)
  defp format_beat(beat), do: to_string(beat)

  defp format_path(nil), do: "—"

  defp format_path(path) when is_list(path) do
    inner = path |> Enum.map_join(" ", &":#{&1}")
    "[#{inner}]"
  end

  defp format_path(path), do: inspect(path)
end
