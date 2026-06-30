defmodule NomosBeamWeb.PianoLive do
  use NomosBeamWeb, :live_view

  @topic "keyboard:events"

  # Physical key → piano key mapping for one chromatic octave (C4–B4).
  # `left` is the CSS left offset (px) within the 280px piano container.
  # White keys: 40px wide × 150px tall.  Black keys: 26px wide × 90px tall.
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

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket), do: Phoenix.PubSub.subscribe(NomosBeam.PubSub, @topic)
    {:ok, assign(socket, pressed: MapSet.new(), keys: @key_layout)}
  end

  @impl true
  def handle_info({:keyboard_state, pressed}, socket) do
    {:noreply, assign(socket, pressed: pressed)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="flex flex-col items-center gap-10 p-10 min-h-screen">
      <header class="font-mono tracking-widest text-base-content/50 text-sm uppercase">
        nomos-studio
      </header>

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
          <span class="piano-key-label"><%= key.phys %></span>
        </div>
      </div>

      <p class="font-mono text-xs text-base-content/30 tracking-widest">
        a · s · d · f · g · h · j &nbsp;→&nbsp; C D E F G A B
      </p>
    </div>
    """
  end
end
