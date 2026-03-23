defmodule LivellmWeb.PageControllerTest do
  use LivellmWeb.ConnCase

  test "GET / renders chat interface", %{conn: conn} do
    conn = get(conn, ~p"/")
    assert html_response(conn, 200) =~ "LiveLLM"
  end
end
