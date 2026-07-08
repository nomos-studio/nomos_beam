# SPDX-FileCopyrightText: 2025-2026 nomos-studio contributors
#
# SPDX-License-Identifier: EPL-2.0

defmodule NomosBeamWeb.NotationLive do
  @moduledoc """
  Notation viewer LiveView — M14.

  Renders txlog note events and corpus works as interactive SVG scores via
  Verovio WASM (client-side). Two tabs:

  **Session** — pick a beat range, click Render; nous.notation extracts
    keyboard key_down events from the txlog, exports via music21, and echoes
    MusicXML back through the ctrl-tree; the VerovioRenderer JS hook renders SVG.

  **Corpus** — pick a BWV number, click Render; nous.notation fetches the
    chorale from music21, exports MusicXML + LilyPond, echoes back; Verovio
    renders SVG; "save pdf" triggers lilypond compilation on the server.

  Data flow:
    Render button
      → NousPort.notation_export_{corpus|session}
      → nous.jinterface :notation_export_{corpus|session}
      → nous.notation/export-{corpus|session}!
      → m21/server-call! → MusicXML string
      → ct/ctrl-write! [:notation ...]
      → BeamMount echo → PubSub "ctrl:notation"
      → handle_info → push_event("render_musicxml_{session|corpus}", %{xml: xml})
      → VerovioRenderer hook → Verovio toolkit → SVG injected in DOM
  """

  use NomosBeamWeb, :live_view

  import NomosBeamWeb.Components.ProcessHealth

  @notation_topic "ctrl:notation"
  @health_topic   "nomos:process:health"

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(NomosBeam.PubSub, @notation_topic)
      Phoenix.PubSub.subscribe(NomosBeam.PubSub, @health_topic)
    end

    {:ok,
     assign(socket,
       tab:             :session,
       beat_from:       0,
       beat_to:         16,
       corpus_bwv:      371,
       rendering:       false,
       pdf_saved:       false,
       health:          [],
       health_expanded: false
     )}
  end

  # ── ctrl:notation events ──────────────────────────────────────────────────

  @impl true
  def handle_info({:ctrl_update, [:notation, :session, :musicxml], xml}, socket) do
    {:noreply,
     socket
     |> assign(rendering: false)
     |> push_event("render_musicxml_session", %{xml: xml})}
  end

  def handle_info({:ctrl_update, [:notation, :corpus, :musicxml], xml}, socket) do
    {:noreply,
     socket
     |> assign(rendering: false)
     |> push_event("render_musicxml_corpus", %{xml: xml})}
  end

  def handle_info({:ctrl_update, [:notation | _], _value}, socket) do
    {:noreply, socket}
  end

  # ── process health ────────────────────────────────────────────────────────

  def handle_info({:process_health, health}, socket) do
    {:noreply, assign(socket, health: health)}
  end

  def handle_info(_msg, socket), do: {:noreply, socket}

  # ── User events ───────────────────────────────────────────────────────────

  @impl true
  def handle_event("set_tab", %{"tab" => tab}, socket) do
    t = String.to_existing_atom(tab)
    {:noreply, assign(socket, tab: t, pdf_saved: false, rendering: false)}
  end

  def handle_event("update_session_range", params, socket) do
    notation = params["notation"] || %{}
    bf = parse_int(notation["beat_from"], socket.assigns.beat_from)
    bt = parse_int(notation["beat_to"],   socket.assigns.beat_to)
    {:noreply, assign(socket, beat_from: bf, beat_to: bt)}
  end

  def handle_event("render_session", _params, socket) do
    NomosBeam.NousPort.notation_export_session(
      socket.assigns.beat_from,
      socket.assigns.beat_to
    )
    {:noreply, assign(socket, rendering: true, pdf_saved: false)}
  end

  def handle_event("update_corpus_bwv", params, socket) do
    notation = params["notation"] || %{}
    bwv = parse_int(notation["corpus_bwv"], socket.assigns.corpus_bwv)
    {:noreply, assign(socket, corpus_bwv: bwv)}
  end

  def handle_event("render_corpus", _params, socket) do
    NomosBeam.NousPort.notation_export_corpus(socket.assigns.corpus_bwv)
    {:noreply, assign(socket, rendering: true)}
  end

  def handle_event("save_pdf", _params, socket) do
    NomosBeam.NousPort.notation_save_session()
    {:noreply, assign(socket, pdf_saved: true)}
  end

  def handle_event("toggle_health", _params, socket) do
    {:noreply, assign(socket, health_expanded: !socket.assigns.health_expanded)}
  end

  def handle_event("health_keydown", %{"key" => "Escape"}, socket) do
    {:noreply, assign(socket, health_expanded: false)}
  end

  def handle_event("health_keydown", _params, socket), do: {:noreply, socket}

  # ── Render ────────────────────────────────────────────────────────────────

  @impl true
  def render(assigns) do
    ~H"""
    <div class="flex flex-col items-center gap-6 p-6 min-h-screen">
      <%!-- Nav + health strip --%>
      <div class="w-full max-w-5xl flex items-center gap-4 px-4 py-2 bg-base-200 rounded font-mono text-xs tracking-widest">
        <span class="text-base-content/65 uppercase">notation</span>
        <a href="/" class="ml-auto text-base-content/55 hover:text-base-content/85">← piano</a>
        <a href="/corpus" class="text-base-content/55 hover:text-base-content/85">corpus</a>
        <a href="/repl" class="text-base-content/55 hover:text-base-content/85">repl</a>
        <.process_health health={@health} expanded={@health_expanded} />
      </div>

      <%!-- Tab switcher --%>
      <div class="w-full max-w-5xl flex gap-1 font-mono text-xs">
        <button phx-click="set_tab" phx-value-tab="session"
                class={["px-4 py-1.5 rounded uppercase tracking-widest transition-colors",
                        @tab == :session && "bg-primary/20 text-primary",
                        @tab != :session && "text-base-content/55 hover:text-base-content/85"]}>
          session
        </button>
        <button phx-click="set_tab" phx-value-tab="corpus"
                class={["px-4 py-1.5 rounded uppercase tracking-widest transition-colors",
                        @tab == :corpus && "bg-primary/20 text-primary",
                        @tab != :corpus && "text-base-content/55 hover:text-base-content/85"]}>
          corpus
        </button>
      </div>

      <%!-- Session tab --%>
      <div class={["w-full max-w-5xl", @tab != :session && "hidden"]}>
        <.form for={%{}} phx-change="update_session_range" phx-submit="render_session"
               class="flex flex-wrap items-center gap-3 mb-4 font-mono text-xs">
          <span class="text-base-content/65 uppercase">beats</span>
          <input type="number" name="notation[beat_from]" value={@beat_from} min="0" step="1"
                 class="w-20 bg-base-200 border border-base-300 rounded px-2 py-1 text-center focus:outline-none focus:border-primary" />
          <span class="text-base-content/55">—</span>
          <input type="number" name="notation[beat_to]" value={@beat_to} min="1" step="1"
                 class="w-20 bg-base-200 border border-base-300 rounded px-2 py-1 text-center focus:outline-none focus:border-primary" />
          <button type="submit"
                  class="tracking-widest uppercase px-4 py-1.5 bg-primary/10 hover:bg-primary/20 text-primary rounded transition-colors">
            render
          </button>
          <button type="button" phx-click="save_pdf"
                  class={["tracking-widest uppercase px-4 py-1.5 rounded transition-colors",
                          @pdf_saved && "bg-success/10 text-success/60 cursor-default",
                          !@pdf_saved && "bg-accent/10 hover:bg-accent/20 text-accent"]}>
            {if @pdf_saved, do: "saved ✓", else: "save pdf"}
          </button>
          <span :if={@rendering && @tab == :session}
                class="text-base-content/55 italic">rendering…</span>
        </.form>
        <div id="verovio-session"
             phx-hook="VerovioRenderer"
             data-render-event="render_musicxml_session"
             phx-update="ignore"
             class="w-full bg-base-200 rounded p-4 min-h-48 overflow-x-auto">
          <p class="text-base-content/45 italic font-mono text-xs verovio-placeholder">
            select a beat range and click render
          </p>
        </div>
      </div>

      <%!-- Corpus tab --%>
      <div class={["w-full max-w-5xl", @tab != :corpus && "hidden"]}>
        <.form for={%{}} phx-change="update_corpus_bwv" phx-submit="render_corpus"
               class="flex flex-wrap items-center gap-3 mb-4 font-mono text-xs">
          <span class="text-base-content/65 uppercase">bwv</span>
          <input type="number" name="notation[corpus_bwv]" value={@corpus_bwv} min="1" step="1"
                 class="w-24 bg-base-200 border border-base-300 rounded px-2 py-1 text-center focus:outline-none focus:border-primary" />
          <button type="submit"
                  class="tracking-widest uppercase px-4 py-1.5 bg-primary/10 hover:bg-primary/20 text-primary rounded transition-colors">
            render
          </button>
          <span :if={@rendering && @tab == :corpus}
                class="text-base-content/55 italic">rendering…</span>
        </.form>
        <div id="verovio-corpus"
             phx-hook="VerovioRenderer"
             data-render-event="render_musicxml_corpus"
             phx-update="ignore"
             class="w-full bg-base-200 rounded p-4 min-h-48 overflow-x-auto">
          <p class="text-base-content/45 italic font-mono text-xs verovio-placeholder">
            enter a BWV number and click render
          </p>
        </div>
      </div>
    </div>
    """
  end

  # ── Private helpers ───────────────────────────────────────────────────────

  defp parse_int(str, default) when is_binary(str) do
    case Integer.parse(str) do
      {n, _} -> n
      :error -> default
    end
  end

  defp parse_int(n, _) when is_integer(n), do: n
  defp parse_int(_, default), do: default
end
