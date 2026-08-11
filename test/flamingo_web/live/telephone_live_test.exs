defmodule FlamingoWeb.TelephoneLiveTest do
  use FlamingoWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Flamingo.{RoomSupervisor, Rooms}

  defp join_connected(room_id, name) do
    parent = self()

    pid =
      start_supervised!(
        Supervisor.child_spec(
          {Task, fn -> connected_player(parent, room_id, name) end},
          id: {:telephone_player, make_ref()}
        )
      )

    assert_receive {:connected, ^pid, token, snapshot}
    Process.put({:telephone_player, token}, pid)
    {token, snapshot}
  end

  defp connected_player(parent, room_id, name) do
    {:ok, token, _snapshot} = Rooms.join(room_id, name)
    {:ok, snapshot} = Rooms.connect(room_id, token)
    send(parent, {:connected, self(), token, snapshot})
    player_loop()
  end

  defp player_loop do
    receive do
      {:call, caller, ref, operation} ->
        send(caller, {ref, operation.()})
        player_loop()

      _room_message ->
        player_loop()
    end
  end

  defp as_player(token, operation) do
    pid = Process.get({:telephone_player, token})
    assert is_pid(pid)
    ref = make_ref()
    send(pid, {:call, self(), ref, operation})
    assert_receive {^ref, result}
    result
  end

  defp command_as(room_id, token, command),
    do: as_player(token, fn -> Rooms.command(room_id, command) end)

  defp draw_event_as(room_id, token, event),
    do: as_player(token, fn -> Rooms.draw_event(room_id, event) end)

  defp snapshot_as(room_id, token),
    do: as_player(token, fn -> Rooms.snapshot(room_id) end)

  defp room_pid(room_id), do: :global.whereis_name({:flamingo_room, room_id})

  defp start_telephone(room_id, host_token, other_token) do
    :ok =
      as_player(host_token, fn ->
        Rooms.start_game(room_id, %{
          game_mode: :telephone,
          turn_length: 30,
          custom_words: ["orbital llama", "velvet cactus"],
          include_default_words: false
        })
      end)

    _ = :sys.get_state(room_pid(room_id))

    {:ok, host_snapshot} = snapshot_as(room_id, host_token)
    {:ok, other_snapshot} = snapshot_as(room_id, other_token)

    :ok =
      command_as(
        room_id,
        host_token,
        {:select_prompt, List.first(host_snapshot.prompt_choices)}
      )

    :ok =
      command_as(
        room_id,
        other_token,
        {:select_prompt, List.first(other_snapshot.prompt_choices)}
      )

    _ = :sys.get_state(room_pid(room_id))
  end

  setup do
    room_id = "telephone-live-#{System.unique_integer([:positive])}"
    {:ok, ^room_id} = RoomSupervisor.start_room(room_id)
    %{room_id: room_id}
  end

  test "host selects Telephone in the lobby and follows the redirect into a private draw", %{
    conn: conn,
    room_id: room_id
  } do
    {host_token, _} = join_connected(room_id, "Alice")
    {other_token, _} = join_connected(room_id, "Bob")
    {:ok, lobby, _html} = live(conn, ~p"/game/#{room_id}?resume_token=#{host_token}")

    lobby
    |> form("#settings-form", %{
      "settings" => %{
        "round_count" => "1",
        "turn_length" => "30",
        "game_mode" => "telephone",
        "custom_words" => "orbital llama\nvelvet cactus",
        "include_default_words" => "false"
      }
    })
    |> render_submit()

    path = "/game/#{room_id}/telephone?resume_token=#{host_token}"
    assert_redirect(lobby, path)
    {:ok, telephone, _html} = live(conn, path)

    assert has_element?(telephone, "#telephone-prompt-phase")
    assert has_element?(telephone, "#telephone-prompt-choices button")

    telephone |> element("#telephone-prompt-choices button", "orbital llama") |> render_click()
    assert has_element?(telephone, "#prompt-submitted-waiting")

    {:ok, other_snapshot} = snapshot_as(room_id, other_token)

    :ok =
      command_as(
        room_id,
        other_token,
        {:select_prompt, List.first(other_snapshot.prompt_choices)}
      )

    _ = :sys.get_state(room_pid(room_id))

    assert has_element?(telephone, "#telephone-draw-phase")

    assert has_element?(telephone, "#draw-source-text", "orbital llama") or
             has_element?(telephone, "#draw-source-text", "velvet cactus")

    assert has_element?(telephone, "#telephone-drawing-canvas canvas")
    assert has_element?(telephone, "#submit-telephone-drawing")
  end

  test "two players receive private chains and progress through draw, guess, and leak-free reveal",
       %{
         conn: conn,
         room_id: room_id
       } do
    {host_token, %{viewer_id: host_id}} = join_connected(room_id, "Alice")
    {bob_token, %{viewer_id: bob_id}} = join_connected(room_id, "Bob")
    start_telephone(room_id, host_token, bob_token)

    {:ok, host, _html} =
      live(conn, ~p"/game/#{room_id}/telephone?resume_token=#{host_token}")

    {:ok, bob_snapshot} = snapshot_as(room_id, bob_token)
    assert bob_snapshot.viewer_id == bob_id
    assert bob_snapshot.assignment.chain_id != nil
    refute has_element?(host, "#draw-source-text", bob_snapshot.assignment.source.value)
    assert host_id != bob_id

    start_event = %{
      "event_type" => "start",
      "x" => 40,
      "y" => 50,
      "color" => "#EF120B",
      "line_width" => 9
    }

    end_event = %{
      "event_type" => "end",
      "start_x" => 40,
      "start_y" => 50,
      "end_x" => 180,
      "end_y" => 160,
      "color" => "#EF120B",
      "line_width" => 9
    }

    host |> element("#telephone-drawing-canvas") |> render_hook("draw_event", start_event)
    host |> element("#telephone-drawing-canvas") |> render_hook("draw_event", end_event)
    :ok = draw_event_as(room_id, bob_token, start_event)
    :ok = draw_event_as(room_id, bob_token, end_event)
    _ = :sys.get_state(room_pid(room_id))

    host |> element("#submit-telephone-drawing") |> render_click()
    assert has_element?(host, "#drawing-submitted-overlay")
    :ok = command_as(room_id, bob_token, :submit_drawing)
    _ = :sys.get_state(room_pid(room_id))

    assert has_element?(host, "#telephone-guess-phase")
    assert has_element?(host, "#telephone-guess-drawing")
    assert has_element?(host, "#telephone-guess-drawing:not([data-final-drawing-events='[]'])")
    assert has_element?(host, "#telephone-guess-drawing svg polyline")
    assert has_element?(host, "#telephone-guess-form")

    host
    |> form("#telephone-guess-form", %{"guess" => %{"text" => "a moon llama"}})
    |> render_submit()

    assert has_element?(host, "#guess-submitted-waiting")
    :ok = command_as(room_id, bob_token, {:submit_guess, "a cactus moon"})
    _ = :sys.get_state(room_pid(room_id))

    assert has_element?(host, "#telephone-reveal-phase")
    assert has_element?(host, "#revealed-entries article")
    refute has_element?(host, "#revealed-entries article:nth-child(2)")
    assert has_element?(host, "#advance-telephone-reveal")

    {:ok, bob_view, _html} =
      live(build_conn(), ~p"/game/#{room_id}/telephone?resume_token=#{bob_token}")

    assert has_element?(bob_view, "#waiting-for-reveal-host")
    refute has_element?(bob_view, "#advance-telephone-reveal")
  end

  test "drawing deltas stay private and reconnect receives the current baseline", %{
    conn: conn,
    room_id: room_id
  } do
    {host_token, _} = join_connected(room_id, "Alice")
    {bob_token, _} = join_connected(room_id, "Bob")
    start_telephone(room_id, host_token, bob_token)
    {:ok, host, _html} = live(conn, ~p"/game/#{room_id}/telephone?resume_token=#{host_token}")
    assert_push_event(host, "drawing_state", %{events: []})

    event = %{
      "event_type" => "start",
      "x" => 12,
      "y" => 34,
      "color" => "#000000",
      "line_width" => 4
    }

    host |> element("#telephone-drawing-canvas") |> render_hook("draw_event", event)
    _ = :sys.get_state(room_pid(room_id))

    {:ok, duplicate, _html} =
      live(build_conn(), ~p"/game/#{room_id}/telephone?resume_token=#{host_token}")

    assert_push_event(duplicate, "drawing_state", %{events: [^event]})
  end

  test "revealed entries can be voted on and the host completes reveal to awards", %{
    conn: conn,
    room_id: room_id
  } do
    {host_token, _} = join_connected(room_id, "Alice")
    {bob_token, _} = join_connected(room_id, "Bob")
    start_telephone(room_id, host_token, bob_token)
    {:ok, host, _html} = live(conn, ~p"/game/#{room_id}/telephone?resume_token=#{host_token}")

    host |> element("#submit-telephone-drawing") |> render_click()
    :ok = command_as(room_id, bob_token, :submit_drawing)
    host |> form("#telephone-guess-form", %{"guess" => %{"text" => "moon"}}) |> render_submit()
    :ok = command_as(room_id, bob_token, {:submit_guess, "cactus"})
    host |> element("#advance-telephone-reveal") |> render_click()

    {:ok, snapshot} = snapshot_as(room_id, host_token)
    drawing = Enum.find(snapshot.reveal.chain.entries, &(&1.type == :drawing))
    vote_id = "vote-worst_drawing-#{drawing.id}"
    assert has_element?(host, "##{vote_id}")
    host |> element("##{vote_id}") |> render_click()
    assert has_element?(host, "##{vote_id}.bg-yellow-200")
    assert has_element?(host, "##{vote_id} span", "1")

    for _ <- 1..5 do
      host |> element("#advance-telephone-reveal") |> render_click()
    end

    assert has_element?(host, "#telephone-awards")
    assert has_element?(host, "#telephone-play-again")
    assert has_element?(host, "#telephone-new-room")
  end

  test "Telephone URL redirects Scribble rooms safely and rejects a bad token", %{
    conn: conn,
    room_id: room_id
  } do
    {host_token, _} = join_connected(room_id, "Alice")
    {_bob_token, _} = join_connected(room_id, "Bob")

    assert {:error, {:live_redirect, %{to: scribble_path}}} =
             live(conn, ~p"/game/#{room_id}/telephone?resume_token=#{host_token}")

    assert scribble_path == "/game/#{room_id}?resume_token=#{host_token}"

    assert {:error, {:live_redirect, %{to: "/"}}} =
             live(build_conn(), ~p"/game/#{room_id}/telephone?resume_token=not-a-token")
  end
end
