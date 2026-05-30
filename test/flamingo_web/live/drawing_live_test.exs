defmodule FlamingoWeb.DrawingLiveTest do
  use FlamingoWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  test "renders the shared drawing shell", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/drawing")

    assert html =~ "id=\"shared-drawing\""
    assert html =~ "id=\"shared-drawing-canvas\""
    assert html =~ "id=\"copy-drawing-link-button\""
    assert html =~ "id=\"replay-shared-drawing-button\""
    refute html =~ "data-final-drawing-replay=\"true\""
  end

  test "does not accept encoded drawing data in the request path", %{conn: conn} do
    conn = get(conn, "/drawing/not-base64")

    assert response(conn, 404)
  end
end
