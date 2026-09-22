defmodule FlamingoWeb.DrawingLiveTest do
  use FlamingoWeb.ConnCase, async: true

  test "does not accept encoded drawing data in the request path", %{conn: conn} do
    conn = get(conn, "/drawing/not-base64")

    assert response(conn, 404)
  end
end
