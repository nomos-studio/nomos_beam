defmodule NomosBeamWeb.PageController do
  use NomosBeamWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
