defmodule FlamingoWeb.PageController do
  use FlamingoWeb, :html_controller

  def index(conn, _params) do
    conn
    |> put_resp_content_type("text/html")
    |> send_file(200, Application.app_dir(:flamingo, "priv/static/index.html"))
  end
end
