defmodule FlamingoWeb.HomeLiveTest do
  use FlamingoWeb.ConnCase, async: true

  import Phoenix.Component
  import Phoenix.LiveViewTest

  alias Flamingo.{Rooms, RoomSupervisor}

  test "room invitation path prefills the room code", %{conn: conn} do
    room_code = "amazing-otter"

    {:ok, view, _html} = live(conn, ~p"/join/#{room_code}")

    assert has_element?(view, "#room-code-input[value='#{room_code}']")
  end

  test "legacy room query does not prefill the room code", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/?room=legacy-code")

    assert has_element?(view, "#room-code-input[value='']")
  end

  test "submitting the lobby form joins when a room name is present", %{conn: conn} do
    room_id = "home-#{System.unique_integer([:positive])}"
    {:ok, ^room_id} = RoomSupervisor.start_room(room_id)

    {:ok, view, _html} = live(conn, ~p"/")

    view
    |> form("#lobby-form",
      lobby: %{
        name: "Alice",
        room_code: room_id,
        head: "1",
        head_color: "6",
        body: "4",
        body_color: "3",
        legs: "2",
        legs_color: "7",
        feet: "3",
        feet_color: "5"
      }
    )
    |> render_submit()

    {path, _flash} = assert_redirect(view)
    uri = URI.parse(path)

    assert uri.path == ~p"/game/#{room_id}"
    assert %{"resume_token" => resume_token} = URI.decode_query(uri.query)
    assert resume_token != ""

    assert {:ok, state} = Rooms.connect(room_id, resume_token)

    assert state.players[state.viewer_id].avatar == %{
             "head" => 1,
             "head_color" => 6,
             "body" => 4,
             "body_color" => 3,
             "legs" => 2,
             "legs_color" => 7,
             "feet" => 3,
             "feet_color" => 5
           }
  end

  test "submitting the lobby form creates when room name is empty", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")

    view
    |> form("#lobby-form", lobby: %{name: "Alice", room_code: ""})
    |> render_submit()

    {path, _flash} = assert_redirect(view)
    uri = URI.parse(path)

    assert uri.path =~ ~r(^/game/.+)
    assert %{"resume_token" => resume_token} = URI.decode_query(uri.query)
    assert resume_token != ""
  end

  test "home action buttons are submit buttons", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")

    assert has_element?(view, "#join-button[type='submit']")
    assert has_element?(view, "#create-room-button[type='submit']")
  end

  test "home lets players mix animal parts and colors without showing every panel", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")

    assert has_element?(view, "#avatar-customizer svg[aria-label='Your customized creature']")
    assert has_element?(view, "#randomize-avatar-button[type='button']")

    for part <- ~w(head body legs feet) do
      assert has_element?(view, "#avatar-part-#{part}[role='tab']")
      assert has_element?(view, "#avatar-#{part}-panel[role='tabpanel']")

      for animal <- 0..4 do
        assert has_element?(
                 view,
                 "input[type='radio'][name='lobby[#{part}]'][value='#{animal}']"
               )
      end

      for color <- 0..7 do
        assert has_element?(
                 view,
                 "input[type='radio'][name='lobby[#{part}_color]'][value='#{color}']"
               )
      end
    end

    assert has_element?(view, "#avatar-head-panel:not([hidden])")
    assert has_element?(view, "#avatar-body-panel[hidden]")

    view |> element("#avatar-part-body") |> render_click()

    assert has_element?(view, "#avatar-head-panel[hidden]")
    assert has_element?(view, "#avatar-body-panel:not([hidden])")
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
             "#sound-volume-slider.nb-slider[type='range'][min='0'][max='100'][step='1'][value='100'][style='--slider-progress: 100.0%']"
           )
           |> Enum.any?()

    assert document
           |> LazyHTML.query("#sound-volume-icon [data-sound-volume-icon]")
           |> Enum.count() >= 2

    refute LazyHTML.text(control) =~ ":"

    refute document |> LazyHTML.query("#sound-toggle-switch") |> Enum.any?()
  end
end
