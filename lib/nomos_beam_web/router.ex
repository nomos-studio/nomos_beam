# SPDX-FileCopyrightText: 2025-2026 nomos-studio contributors
#
# SPDX-License-Identifier: EPL-2.0

defmodule NomosBeamWeb.Router do
  use NomosBeamWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {NomosBeamWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/", NomosBeamWeb do
    pipe_through :browser

    live "/", PianoLive
    live "/corpus", CorpusLive
    live "/repl", ReplLive
    live "/notation", NotationLive
  end

  # Other scopes may use custom stacks.
  # scope "/api", NomosBeamWeb do
  #   pipe_through :api
  # end
end
