# SPDX-FileCopyrightText: 2025-2026 nomos-studio contributors
#
# SPDX-License-Identifier: EPL-2.0

defmodule NomosBeamWeb.CorpusLive do
  @moduledoc """
  Corpora browser LiveView — M10.

  Displays the Bach chorale corpus from music21, lets the user browse by BWV
  number, inspect key/mode/time-sig/measure metadata, and apply a work's
  theory context (root + mode) to the live ctrl-tree with one click.

  Data flow:
    mount → NousPort.corpus_query(:list_chorales)
          → nous writes [:corpus :chorales] JSON
          → BeamMount echo → PubSub "ctrl:corpus"
          → handle_info updates assigns

    select_chorale → NousPort.corpus_query({:metadata, bwv})
                   → nous writes [:corpus :selected_metadata] JSON
                   → echo → assigns

    apply_theory   → NousPort.ctrl_write([:theory, :root], key)
                   → NousPort.ctrl_write([:theory, :mode], mode)
                   → BeamMount echo → PubSub "ctrl:transport"
                   → PianoLive / CorpusLive status strip update
  """

  use NomosBeamWeb, :live_view

  import NomosBeamWeb.Components.ProcessHealth

  @corpus_topic    "ctrl:corpus"
  @transport_topic "ctrl:transport"
  @health_topic    "nomos:process:health"

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(NomosBeam.PubSub, @corpus_topic)
      Phoenix.PubSub.subscribe(NomosBeam.PubSub, @transport_topic)
      Phoenix.PubSub.subscribe(NomosBeam.PubSub, @health_topic)
      NomosBeam.NousPort.corpus_query(:list_chorales)
    end

    {:ok,
     assign(socket,
       chorales:       nil,
       selected_bwv:   nil,
       metadata:       nil,
       theory_key:     nil,
       theory_mode:    nil,
       applying:       false,
       loading_meta:   false,
       health:         [],
       health_expanded: false
     )}
  end

  # ── ctrl:corpus events ────────────────────────────────────────────────────

  @impl true
  def handle_info({:ctrl_update, [:corpus, :chorales], json_str}, socket) do
    chorales = Jason.decode!(json_str)
    {:noreply, assign(socket, chorales: chorales)}
  end

  def handle_info({:ctrl_update, [:corpus, :selected_metadata], json_str}, socket) do
    meta = Jason.decode!(json_str, keys: :atoms)
    {:noreply, assign(socket, metadata: meta, loading_meta: false)}
  end

  def handle_info({:ctrl_update, [:corpus | _], _value}, socket) do
    {:noreply, socket}
  end

  # ── ctrl:transport / theory events ───────────────────────────────────────

  def handle_info({:ctrl_update, [:theory, :key], value}, socket) do
    {:noreply, assign(socket, theory_key: value, applying: false)}
  end

  def handle_info({:ctrl_update, [:theory, :mode], value}, socket) do
    {:noreply, assign(socket, theory_mode: value)}
  end

  def handle_info({:ctrl_update, _path, _value}, socket) do
    {:noreply, socket}
  end

  # ── process health ────────────────────────────────────────────────────────

  def handle_info({:process_health, health}, socket) do
    {:noreply, assign(socket, health: health)}
  end

  # ── User events ───────────────────────────────────────────────────────────

  @impl true
  def handle_event("select_chorale", %{"bwv" => bwv_str}, socket) do
    bwv = String.to_integer(bwv_str)
    NomosBeam.NousPort.corpus_query(%{metadata: bwv})
    {:noreply, assign(socket, selected_bwv: bwv, metadata: nil, loading_meta: true)}
  end

  def handle_event("apply_theory", _params, socket) do
    case socket.assigns.metadata do
      %{key: key, mode: mode} ->
        NomosBeam.NousPort.ctrl_write([:theory, :key], key)
        NomosBeam.NousPort.ctrl_write([:theory, :mode], mode)
        {:noreply, assign(socket, applying: true)}
      _ ->
        {:noreply, socket}
    end
  end

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
    <div class="flex flex-col items-center gap-8 p-10 min-h-screen">
      <%!-- Status strip (mirrors PianoLive) --%>
      <div class="w-full max-w-3xl flex items-center gap-5 px-4 py-2 bg-base-200 rounded font-mono text-xs tracking-widest">
        <span class="text-base-content/65 uppercase">key</span>
        <span class="text-accent">{@theory_key || "—"}</span>
        <span class="text-accent/80">{@theory_mode || ""}</span>
        <a href="/" class="ml-auto text-base-content/55 hover:text-base-content/85 text-xs font-mono tracking-widest">
          ← piano
        </a>
        <a href="/repl" class="text-base-content/55 hover:text-base-content/85 text-xs font-mono tracking-widest">repl</a>
        <a href="/notation" class="text-base-content/55 hover:text-base-content/85 text-xs font-mono tracking-widest">notation</a>
        <.process_health health={@health} expanded={@health_expanded} />
      </div>

      <header class="font-mono tracking-widest text-base-content/70 text-sm uppercase">
        corpora browser
      </header>

      <div class="w-full max-w-3xl flex gap-6">
        <%!-- Chorale list --%>
        <div class="flex-1 min-w-0">
          <h2 class="font-mono text-xs text-base-content/65 tracking-widest uppercase mb-2">
            bach chorales
            <span :if={@chorales} class="text-base-content/45 ml-2">({length(@chorales)})</span>
          </h2>
          <div class="bg-base-200 rounded p-2 h-96 overflow-y-auto">
            <p :if={is_nil(@chorales)} class="text-base-content/45 italic font-mono text-xs p-2">
              waiting for m21 server…
            </p>
            <div
              :for={bwv <- (@chorales || [])}
              class={[
                "font-mono text-xs px-3 py-1 rounded cursor-pointer select-none",
                "hover:bg-base-300 transition-colors",
                @selected_bwv == bwv && "bg-primary/20 text-primary"
              ]}
              phx-click="select_chorale"
              phx-value-bwv={bwv}
            >
              BWV {bwv}
            </div>
          </div>
        </div>

        <%!-- Metadata panel --%>
        <div class="w-64 shrink-0">
          <h2 class="font-mono text-xs text-base-content/65 tracking-widest uppercase mb-2">
            metadata
          </h2>
          <div class="bg-base-200 rounded p-4 h-96 flex flex-col gap-3">
            <p :if={is_nil(@selected_bwv)} class="text-base-content/45 italic font-mono text-xs">
              select a work
            </p>

            <p :if={@loading_meta && !@metadata} class="text-base-content/55 italic font-mono text-xs">
              analysing…
            </p>

            <div :if={@metadata} class="flex flex-col gap-2 font-mono text-xs">
              <div>
                <span class="text-base-content/65 uppercase">bwv</span>
                <span class="text-base-content ml-2">{@metadata[:bwv]}</span>
              </div>
              <div :if={@metadata[:title] != ""}>
                <span class="text-base-content/65 uppercase">title</span>
                <span class="text-base-content/85 ml-2">{@metadata[:title]}</span>
              </div>
              <div>
                <span class="text-base-content/65 uppercase">key</span>
                <span class="text-accent ml-2">{@metadata[:key]}</span>
                <span class="text-accent/80 ml-1">{@metadata[:mode]}</span>
              </div>
              <div>
                <span class="text-base-content/65 uppercase">time</span>
                <span class="text-base-content ml-2">{@metadata[:"time-sig"]}</span>
              </div>
              <div>
                <span class="text-base-content/65 uppercase">bars</span>
                <span class="text-base-content ml-2">{@metadata[:measures]}</span>
              </div>

              <div class="mt-auto pt-2 border-t border-base-300">
                <button
                  phx-click="apply_theory"
                  class={[
                    "w-full font-mono text-xs tracking-widest uppercase px-3 py-2 rounded",
                    "transition-colors",
                    @applying && "bg-primary/30 text-primary/60 cursor-default",
                    !@applying && "bg-primary/10 hover:bg-primary/20 text-primary cursor-pointer"
                  ]}
                  disabled={@applying}
                >
                  {if @applying, do: "applying…", else: "apply to session"}
                </button>
              </div>
            </div>
          </div>
        </div>
      </div>
    </div>
    """
  end
end
