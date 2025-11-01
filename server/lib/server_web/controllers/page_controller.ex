defmodule ServerWeb.PageController do
  use ServerWeb, :html_controller

  def index(conn, _params) do
    conn
    |> put_resp_content_type("text/html")
    |> send_file(200, Application.app_dir(:server, "priv/static/index.html"))
  end
end
