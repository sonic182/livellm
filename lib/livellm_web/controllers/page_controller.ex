defmodule LivellmWeb.PageController do
  use LivellmWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
