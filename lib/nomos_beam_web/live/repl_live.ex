# SPDX-FileCopyrightText: 2025-2026 nomos-studio contributors
#
# SPDX-License-Identifier: EPL-2.0

defmodule NomosBeamWeb.ReplLive do
  @moduledoc """
  Browser REPL + session notes LiveView — M11.

  Provides two panels side by side:

  **REPL panel** — evaluate Clojure forms from the browser.
    Input  : form string submitted via phx-submit
    Path   : Phoenix WebSocket → NousPort.repl_eval/1 → jinterface :repl_eval
             → nous eval → [:repl :last_result] ctrl-tree write
             → BeamMount echo → PubSub "ctrl:repl" → this LiveView
    Output : appends {form, value|error} to scrolling history (max 50)

  **Notes panel** — session notes (notes.md).
    Path   : nous writes [:session :notes_path] on session start
             → PubSub "ctrl:session" → this LiveView knows the path
    Auto-save: textarea change event → File.write!/2 directly from BEAM
    First open: template created by nous.core/init-session-notes!

  Emacs users connect directly to the nREPL TCP server on port 7888
  (M-x cider-connect localhost 7888) — this panel is an additional surface,
  not a replacement.
  """

  use NomosBeamWeb, :live_view

  import NomosBeamWeb.Components.ProcessHealth

  @repl_topic    "ctrl:repl"
  @session_topic "ctrl:session"
  @health_topic  "nomos:process:health"
  @max_history   50

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(NomosBeam.PubSub, @repl_topic)
      Phoenix.PubSub.subscribe(NomosBeam.PubSub, @session_topic)
      Phoenix.PubSub.subscribe(NomosBeam.PubSub, @health_topic)
    end

    {:ok,
     socket
     |> assign(
          input:          "",
          notes_path:     nil,
          notes_content:  "",
          pending_eval:   false,
          health:         [],
          health_expanded: false
        )
     |> stream(:history, [])}
  end

  # ── ctrl:repl events ─────────────────────────────────────────────────────

  @impl true
  def handle_info({:ctrl_update, [:repl, :last_result], json_str}, socket) do
    result = Jason.decode!(json_str, keys: :atoms)
    entry  = %{
      id:    System.unique_integer([:positive, :monotonic]),
      form:  result[:form]  || "",
      value: result[:value],
      error: result[:error],
      out:   result[:out],
      err:   result[:err]
    }
    {:noreply,
     socket
     |> stream_insert(:history, entry, limit: @max_history)
     |> assign(pending_eval: false)}
  end

  def handle_info({:ctrl_update, [:repl | _], _value}, socket) do
    {:noreply, socket}
  end

  # ── ctrl:session events ──────────────────────────────────────────────────

  def handle_info({:ctrl_update, [:session, :notes_path], path}, socket) do
    content = case File.read(path) do
      {:ok, text} -> text
      _           -> ""
    end
    {:noreply, assign(socket, notes_path: path, notes_content: content)}
  end

  def handle_info({:ctrl_update, [:session | _], _value}, socket) do
    {:noreply, socket}
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
  def handle_event("eval_submit", %{"form" => form}, socket) do
    form = String.trim(form)
    if form == "" do
      {:noreply, socket}
    else
      NomosBeam.NousPort.repl_eval(form)
      {:noreply, assign(socket, input: "", pending_eval: true)}
    end
  end

  def handle_event("update_input", %{"form" => form}, socket) do
    {:noreply, assign(socket, input: form)}
  end

  def handle_event("save_notes", %{"content" => content}, socket) do
    if socket.assigns.notes_path do
      File.write!(socket.assigns.notes_path, content)
    end
    {:noreply, assign(socket, notes_content: content)}
  end

  def handle_event("clear_history", _params, socket) do
    {:noreply, stream(socket, :history, [], reset: true)}
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
    <div class="flex flex-col items-center gap-6 p-8 min-h-screen">
      <%!-- Nav + health strip --%>
      <div class="w-full max-w-5xl flex items-center gap-4 px-4 py-2 bg-base-200 rounded font-mono text-xs tracking-widest">
        <span class="text-base-content/40 uppercase">repl</span>
        <span :if={@pending_eval} class="text-primary/60 italic">evaluating…</span>
        <a href="/" class="ml-auto text-base-content/30 hover:text-base-content/60">← piano</a>
        <a href="/corpus" class="text-base-content/30 hover:text-base-content/60">corpus</a>
        <a href="/notation" class="text-base-content/30 hover:text-base-content/60">notation</a>
        <.process_health health={@health} expanded={@health_expanded} />
      </div>

      <div class="w-full max-w-5xl flex gap-6">
        <%!-- REPL panel --%>
        <div class="flex-1 min-w-0 flex flex-col gap-3">
          <h2 class="font-mono text-xs text-base-content/40 tracking-widest uppercase">
            clojure repl
            <span class="text-base-content/20 ml-2 normal-case">nREPL also on localhost:7888</span>
          </h2>

          <%!-- Output history --%>
          <div
            id="repl-output"
            class="bg-base-200 rounded p-3 h-80 overflow-y-auto font-mono text-xs flex flex-col gap-2"
          >
            <p :if={Enum.empty?(@streams.history.inserts)} class="text-base-content/20 italic" id="repl-empty">
              waiting for nous session… (call (session!) in CIDER or terminal)
            </p>
            <div :for={{dom_id, entry} <- @streams.history} id={dom_id}>
              <div class="text-base-content/50">
                <span class="text-primary/60">⟹</span>
                <span class="ml-1">{entry.form}</span>
              </div>
              <div :if={entry.out && entry.out != ""} class="text-base-content/40 ml-4 whitespace-pre-wrap">
                {entry.out}
              </div>
              <div :if={entry.value} class="text-accent ml-4">{entry.value}</div>
              <div :if={entry.error} class="text-error ml-4">{entry.error}</div>
            </div>
          </div>

          <%!-- Input --%>
          <.form for={%{}} phx-submit="eval_submit" class="flex gap-2">
            <input
              type="text"
              name="form"
              value={@input}
              phx-change="update_input"
              placeholder="(+ 1 2)"
              class="flex-1 font-mono text-xs bg-base-200 border border-base-300 rounded px-3 py-2 focus:outline-none focus:border-primary"
              autocomplete="off"
              spellcheck="false"
            />
            <button
              type="submit"
              class="font-mono text-xs tracking-widest uppercase px-4 py-2 bg-primary/10 hover:bg-primary/20 text-primary rounded transition-colors"
            >
              eval
            </button>
            <button
              type="button"
              phx-click="clear_history"
              class="font-mono text-xs text-base-content/30 hover:text-base-content/60 px-2"
            >
              clear
            </button>
          </.form>
        </div>

        <%!-- Notes panel --%>
        <div class="w-72 shrink-0 flex flex-col gap-3">
          <h2 class="font-mono text-xs text-base-content/40 tracking-widest uppercase">
            session notes
            <span :if={@notes_path} class="text-base-content/20 ml-2 normal-case truncate">
              {Path.basename(@notes_path)}
            </span>
          </h2>
          <p :if={is_nil(@notes_path)} class="text-base-content/20 italic font-mono text-xs">
            waiting for session start…
          </p>
          <textarea
            :if={@notes_path}
            name="content"
            phx-change="save_notes"
            class="w-full h-80 font-mono text-xs bg-base-200 border border-base-300 rounded p-3 resize-none focus:outline-none focus:border-primary"
            spellcheck="false"
          >{@notes_content}</textarea>
          <p :if={@notes_path} class="font-mono text-xs text-base-content/20">
            auto-saves on change · git tracks {Path.basename(@notes_path)}
          </p>
        </div>
      </div>
    </div>
    """
  end
end
