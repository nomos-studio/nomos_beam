# SPDX-FileCopyrightText: 2025-2026 nomos-studio contributors
#
# SPDX-License-Identifier: EPL-2.0

defmodule NomosBeamWeb.PageController do
  use NomosBeamWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
