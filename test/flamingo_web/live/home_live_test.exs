defmodule FlamingoWeb.HomeLiveTest do
  use FlamingoWeb.ConnCase, async: true

  import Phoenix.Component
  import Phoenix.LiveViewTest

  alias Flamingo.RoomSupervisor

  test "submitting the lobby form joins when a room name is present", %{conn: conn} do
    room_id = "home-#{System.unique_integer([:positive])}"
    {:ok, ^room_id} = RoomSupervisor.start_room(room_id)

    {:ok, view, _html} = live(conn, ~p"/")

    view
    |> form("#lobby-form", lobby: %{name: "Alice", room_code: room_id})
    |> render_submit()

    {path, _flash} = assert_redirect(view)
    uri = URI.parse(path)

    assert uri.path == ~p"/game/#{room_id}"
    assert %{"player_id" => player_id} = URI.decode_query(uri.query)
    assert player_id != ""
  end

  test "submitting the lobby form creates when room name is empty", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")

    view
    |> form("#lobby-form", lobby: %{name: "Alice", room_code: ""})
    |> render_submit()

    {path, _flash} = assert_redirect(view)
    uri = URI.parse(path)

    assert uri.path =~ ~r(^/game/.+)
    assert %{"player_id" => player_id} = URI.decode_query(uri.query)
    assert player_id != ""
  end

  test "home action buttons are submit buttons", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/")

    assert html =~ ~s(id="join-button")
    assert html =~ ~s(id="create-room-button")
    assert html =~ ~s(type="submit")
  end

  test "app layout sound control is a volume slider initialized to full volume" do
    assigns = %{}

    html =
      rendered_to_string(~H"""
      <FlamingoWeb.Layouts.app flash={%{}}>
        <div id="layout-child"></div>
      </FlamingoWeb.Layouts.app>
      """)

    document = LazyHTML.from_fragment(html)

    control = document |> LazyHTML.query("#sound-volume-control")
    assert control |> Enum.any?()

    [control_class] = LazyHTML.attribute(control, "class")
    assert control_class =~ "bg-white"
    assert control_class =~ "border"
    assert control_class =~ "shadow"

    assert document
           |> LazyHTML.query(
             "#sound-volume-button[type='button'][aria-label='Toggle sound mute']"
           )
           |> Enum.any?()

    assert document
           |> LazyHTML.query(
             "#sound-volume-slider.nb-slider[type='range'][min='0'][max='100'][step='1'][value='100']"
           )
           |> Enum.any?()

    assert document
           |> LazyHTML.query("#sound-volume-icon [data-sound-volume-icon]")
           |> Enum.count() >= 2

    refute LazyHTML.text(control) =~ ":"

    refute document |> LazyHTML.query("#sound-toggle-switch") |> Enum.any?()
  end
end
