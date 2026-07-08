# SPDX-FileCopyrightText: 2025-2026 nomos-studio contributors
#
# SPDX-License-Identifier: EPL-2.0

defmodule NomosBeamWeb.Components.ProcessHealth do
  @moduledoc """
  Expando-matter component for process health — M13.

  Condensed: one coloured dot per supervised process, always visible.
  Expanded: full detail panel showing process name, status, and socket note.

  Toggled by phx-click="toggle_health" on the condensed row. The parent
  LiveView owns the expanded/collapsed state (health_expanded assign) and
  handles handle_event("toggle_health", ...) and handle_event("health_keydown", ...).

  Usage in a LiveView template:

      <.process_health health={@health} expanded={@health_expanded} />

  The parent LiveView must:
    - subscribe to "nomos:process:health" and handle {:process_health, health}
    - assign health: [] and health_expanded: false in mount
    - implement handle_event("toggle_health", ...) and handle_event("health_keydown", ...)
  """

  use NomosBeamWeb, :html

  attr :health, :list, default: []
  attr :expanded, :boolean, default: false

  def process_health(assigns) do
    ~H"""
    <div class="relative">
      <%!-- Condensed dot row — always visible --%>
      <div
        class="flex items-center gap-1.5 cursor-pointer select-none group"
        phx-click="toggle_health"
        title="Process health — click to expand"
      >
        <span class="text-base-content/50 text-xs font-mono tracking-widest uppercase group-hover:text-base-content/70 transition-colors">
          health
        </span>
        <span :for={svc <- @health} class="flex items-center">
          <span
            class={["w-2 h-2 rounded-full transition-colors", dot_class(svc.status)]}
            title={"#{svc.label}: #{svc.status}"}
          >
          </span>
        </span>
      </div>

      <%!-- Expanded detail panel --%>
      <div
        :if={@expanded}
        class="absolute right-0 top-7 z-50 min-w-[13rem] bg-base-300 border border-base-content/10 rounded shadow-lg font-mono text-xs p-3"
        phx-window-keydown="health_keydown"
      >
        <div class="flex items-center justify-between mb-2.5">
          <span class="text-base-content/60 uppercase tracking-widest text-[10px]">process health</span>
          <button
            class="text-base-content/55 hover:text-base-content/85 leading-none px-1"
            phx-click="toggle_health"
          >×</button>
        </div>
        <table class="w-full border-collapse">
          <tbody>
            <tr :for={svc <- @health} class="align-middle">
              <td class="pr-2 py-0.5">
                <span class={["inline-block w-1.5 h-1.5 rounded-full", dot_class(svc.status)]}></span>
              </td>
              <td class="pr-3 py-0.5 text-base-content/80">{svc.label}</td>
              <td class={"py-0.5 #{status_text_class(svc.status)}"}>{svc.status}</td>
              <td :if={svc.note} class="py-0.5 pl-2 text-base-content/50 truncate max-w-[6rem]">
                {svc.note}
              </td>
            </tr>
          </tbody>
        </table>
      </div>
    </div>
    """
  end

  defp dot_class(:up),       do: "bg-success"
  defp dot_class(:down),     do: "bg-error"
  defp dot_class(:disabled), do: "bg-base-content/35"

  defp status_text_class(:up),       do: "text-success"
  defp status_text_class(:down),     do: "text-error"
  defp status_text_class(:disabled), do: "text-base-content/50"
end
