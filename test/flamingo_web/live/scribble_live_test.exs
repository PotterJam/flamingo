defmodule FlamingoWeb.ScribbleLiveTest do
  use FlamingoWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Flamingo.DrawingShare
  alias Flamingo.RoomServer

  defp join_connected(room_id, player_name) do
    parent = self()
    child_id = {:player, make_ref()}

    pid =
      start_supervised!(
        Supervisor.child_spec(
          {Task, fn -> join_player(parent, room_id, player_name) end},
          id: child_id
        )
      )

    assert_receive {:player_connected, ^pid, {:ok, resume_token, snapshot}}
    Process.put({:player, resume_token}, pid)
    {:ok, resume_token, snapshot}
  end

  defp join_player(parent, room_id, player_name) do
    {:ok, resume_token, _snapshot} = RoomServer.join(room_id, player_name)
    {:ok, snapshot} = RoomServer.connect(room_id, resume_token)
    send(parent, {:player_connected, self(), {:ok, resume_token, snapshot}})
    player_loop(parent)
  end

  defp player_loop(parent) do
    receive do
      {:call, caller, ref, operation} ->
        send(caller, {ref, operation.()})
        player_loop(parent)

      {:room_snapshot, snapshot} ->
        send(parent, {:room_snapshot, snapshot})
        player_loop(parent)

      {:draw_event, event} ->
        send(parent, {:draw_event, self(), event})
        player_loop(parent)
    end
  end

  defp as_player(resume_token, operation) do
    pid = Process.get({:player, resume_token})
    ref = make_ref()
    send(pid, {:call, self(), ref, operation})
    assert_receive {^ref, result}
    result
  end

  defp start_game_as(room_id, token, settings),
    do: as_player(token, fn -> RoomServer.start_game(room_id, settings) end)

  defp select_word_as(room_id, token, word),
    do: as_player(token, fn -> RoomServer.select_word(room_id, word) end)

  defp guess_as(room_id, token, guess),
    do: as_player(token, fn -> RoomServer.guess(room_id, guess) end)

  defp draw_event_as(room_id, token, event),
    do: as_player(token, fn -> RoomServer.draw_event(room_id, event) end)

  defp snapshot_as(room_id, token),
    do: as_player(token, fn -> RoomServer.snapshot(room_id) end)

  defp leave_as(room_id, token), do: as_player(token, fn -> RoomServer.leave(room_id) end)

  alias Flamingo.RoomSupervisor

  setup do
    room_id = "live-#{System.unique_integer([:positive])}"
    {:ok, ^room_id} = RoomSupervisor.start_room(room_id)
    %{room_id: room_id}
  end

  test "host settings clamp round length to supported bounds", %{conn: conn, room_id: room_id} do
    {:ok, p1_token, _p1_snapshot} = join_connected(room_id, "Alice")
    {:ok, _p2_token, _p2_snapshot} = join_connected(room_id, "Bob")

    {:ok, view, _html} = live(conn, ~p"/game/#{room_id}?resume_token=#{p1_token}")

    assert has_element?(view, "#round-length-input[min='15'][max='120']")

    view
    |> element("#settings-form")
    |> render_change(%{"settings" => %{"round_count" => "3", "turn_length" => "14"}})

    assert has_element?(view, "#round-length-input[value='15']")

    view
    |> element("#settings-form")
    |> render_change(%{"settings" => %{"round_count" => "3", "turn_length" => "121"}})

    assert has_element?(view, "#round-length-input[value='120']")
  end

  test "host can configure custom words one per line", %{conn: conn, room_id: room_id} do
    {:ok, p1_token, _p1_snapshot} = join_connected(room_id, "Alice")
    {:ok, _p2_token, _p2_snapshot} = join_connected(room_id, "Bob")

    {:ok, view, _html} = live(conn, ~p"/game/#{room_id}?resume_token=#{p1_token}")

    assert has_element?(view, "#custom-words-input[placeholder*='one per line']")
    assert has_element?(view, "#include-default-words-input:not(:checked)")

    view
    |> form("#settings-form", %{
      "settings" => %{
        "round_count" => "3",
        "turn_length" => "45",
        "custom_words" => "orbital llama\nvelvet cactus\ndisco teapot",
        "include_default_words" => "true"
      }
    })
    |> render_submit()

    {:ok, state} = RoomServer.get_state(room_id)
    assert state.game.custom_words == ["orbital llama", "velvet cactus", "disco teapot"]
    assert state.game.include_default_words
  end

  test "custom word validation is shown before starting", %{conn: conn, room_id: room_id} do
    {:ok, p1_token, _p1_snapshot} = join_connected(room_id, "Alice")
    {:ok, _p2_token, _p2_snapshot} = join_connected(room_id, "Bob")

    {:ok, view, _html} = live(conn, ~p"/game/#{room_id}?resume_token=#{p1_token}")

    view
    |> element("#settings-form")
    |> render_change(%{
      "settings" => %{
        "round_count" => "3",
        "turn_length" => "45",
        "custom_words" => "cat, dog"
      }
    })

    assert has_element?(view, "#custom-words-error")
  end

  test "a lobby update does not replace the host's unsaved settings", %{
    conn: conn,
    room_id: room_id
  } do
    {:ok, host_token, _snapshot} = join_connected(room_id, "Alice")
    {:ok, view, _html} = live(conn, ~p"/game/#{room_id}?resume_token=#{host_token}")

    view
    |> element("#settings-form")
    |> render_change(%{
      "settings" => %{
        "round_count" => "5",
        "turn_length" => "90",
        "custom_words" => "saved locally"
      }
    })

    {:ok, _bob_token, _snapshot} = join_connected(room_id, "Bob")

    assert has_element?(view, "#round-count-slider[value='5']")
    assert has_element?(view, "#round-length-input[value='90']")
    assert has_element?(view, "#custom-words-input", "saved locally")
  end

  test "guesser receives a projected word while the drawer sees the selected word", %{
    conn: conn,
    room_id: room_id
  } do
    {:ok, drawer_id_token, %{viewer_id: drawer_id}} = join_connected(room_id, "Alice")
    {:ok, guesser_id_token, %{viewer_id: guesser_id}} = join_connected(room_id, "Bob")

    {:ok, drawer_view, _html} =
      live(conn, ~p"/game/#{room_id}?resume_token=#{drawer_id_token}")

    {:ok, guesser_view, _html} =
      live(conn, ~p"/game/#{room_id}?resume_token=#{guesser_id_token}")

    resume_tokens = %{drawer_id => drawer_id_token, guesser_id => guesser_id_token}

    :ok =
      start_game_as(room_id, Map.fetch!(resume_tokens, drawer_id), %{
        custom_words: ["secret", "other", "third"],
        round_count: 1,
        turn_length: 30
      })

    {:ok, state} = RoomServer.get_state(room_id)
    word = List.first(state.game.word_choices)
    :ok = select_word_as(room_id, Map.fetch!(resume_tokens, drawer_id), word)

    assert render(drawer_view) =~ word
    refute render(guesser_view) =~ word
    assert has_element?(guesser_view, "#guess-input")

    guesser_view
    |> form("#guess-form", %{"guess_form" => %{"guess" => "wrong answer"}})
    |> render_submit()

    assert_push_event(guesser_view, "play_sound", %{sound: "wrongGuess"})
  end

  test "drawing events are incremental and excluded only from their originating tab", %{
    conn: conn,
    room_id: room_id
  } do
    {:ok, drawer_token, _drawer_snapshot} = join_connected(room_id, "Alice")
    {:ok, guesser_token, _guesser_snapshot} = join_connected(room_id, "Bob")

    {:ok, drawer_view, _html} = live(conn, ~p"/game/#{room_id}?resume_token=#{drawer_token}")
    {:ok, duplicate_view, _html} = live(conn, ~p"/game/#{room_id}?resume_token=#{drawer_token}")
    {:ok, guesser_view, _html} = live(conn, ~p"/game/#{room_id}?resume_token=#{guesser_token}")

    :ok =
      start_game_as(room_id, drawer_token, %{
        custom_words: ["secret", "other", "third"]
      })

    {:ok, state} = RoomServer.get_state(room_id)
    word = List.first(state.game.word_choices)
    :ok = select_word_as(room_id, drawer_token, word)

    assert_push_event(drawer_view, "drawing_state", %{events: []})
    assert_push_event(duplicate_view, "drawing_state", %{events: []})
    assert_push_event(guesser_view, "drawing_state", %{events: []})

    event = %{"event_type" => "clear"}
    render_hook(drawer_view, "draw_event", event)
    _ = :sys.get_state(RoomServer.whereis(room_id))

    refute_push_event(drawer_view, "draw_event", ^event)
    assert_push_event(duplicate_view, "draw_event", ^event)
    assert_push_event(guesser_view, "draw_event", ^event)
    refute_push_event(drawer_view, "drawing_state", %{})
    refute_push_event(duplicate_view, "drawing_state", %{})
    refute_push_event(guesser_view, "drawing_state", %{})

    guesser_view
    |> form("#guess-form", %{"guess_form" => %{"guess" => "wrong answer"}})
    |> render_submit()

    refute_push_event(drawer_view, "drawing_state", %{})
    refute_push_event(duplicate_view, "drawing_state", %{})
    refute_push_event(guesser_view, "drawing_state", %{})

    {:ok, state} = RoomServer.get_state(room_id)
    assert state.game.current_drawing == [event]
  end

  test "a late connection receives the complete drawing baseline", %{
    conn: conn,
    room_id: room_id
  } do
    {:ok, drawer_token, _drawer_snapshot} = join_connected(room_id, "Alice")
    {:ok, guesser_token, _guesser_snapshot} = join_connected(room_id, "Bob")

    :ok =
      start_game_as(room_id, drawer_token, %{
        custom_words: ["secret", "other", "third"]
      })

    {:ok, state} = RoomServer.get_state(room_id)
    :ok = select_word_as(room_id, drawer_token, List.first(state.game.word_choices))

    first_event = %{"event_type" => "clear"}
    second_event = %{"event_type" => "fill", "x" => 10, "y" => 20, "color" => "#000000"}
    draw_event_as(room_id, drawer_token, first_event)
    draw_event_as(room_id, drawer_token, second_event)
    _ = :sys.get_state(RoomServer.whereis(room_id))

    {:ok, guesser_view, _html} = live(conn, ~p"/game/#{room_id}?resume_token=#{guesser_token}")

    assert_push_event(guesser_view, "drawing_state", %{events: [^first_event, ^second_event]})
  end

  test "game end screen keeps final scores visible after a player leaves", %{
    conn: conn,
    room_id: room_id
  } do
    {:ok, p1_token, %{viewer_id: p1}} = join_connected(room_id, "Alice")
    {:ok, p2_token, %{viewer_id: p2}} = join_connected(room_id, "Bob")

    {:ok, view, _html} = live(conn, ~p"/game/#{room_id}?resume_token=#{p1_token}")

    resume_tokens = %{p1 => p1_token, p2 => p2_token}

    :ok =
      start_game_as(room_id, Map.fetch!(resume_tokens, p1), %{
        round_count: 1,
        turn_length: 30
      })

    play_turn(room_id, p1, p1_token, p2, p2_token)
    play_turn(room_id, p1, p1_token, p2, p2_token)

    html = render(view)
    assert html =~ "Game finished"
    assert html =~ "Alice"
    assert html =~ "Bob"

    :ok = leave_as(room_id, Map.fetch!(resume_tokens, p2))

    html = render(view)
    assert html =~ "Game finished"
    assert html =~ "Alice"
    assert html =~ "Bob"

    {:ok, snapshot} = snapshot_as(room_id, p1_token)
    refute Map.has_key?(snapshot.players, p2)
    assert snapshot.final_player_order == [p1, p2]
    assert Map.fetch!(snapshot.final_players, p1).score > 0
    assert Map.fetch!(snapshot.final_players, p2).score > 0

    {:ok, reconnected_view, _html} =
      live(conn, ~p"/game/#{room_id}?resume_token=#{p1_token}")

    assert has_element?(reconnected_view, "#final-score-rows [data-player-id='#{p1}']")
    assert has_element?(reconnected_view, "#final-score-rows [data-player-id='#{p2}']")
  end

  test "game end screen shows the winning player's drawings", %{conn: conn, room_id: room_id} do
    {:ok, p1_token, %{viewer_id: p1}} = join_connected(room_id, "Alice")
    {:ok, p2_token, %{viewer_id: p2}} = join_connected(room_id, "Bob")

    {:ok, view, _html} = live(conn, ~p"/game/#{room_id}?resume_token=#{p1_token}")

    resume_tokens = %{p1 => p1_token, p2 => p2_token}

    :ok =
      start_game_as(room_id, Map.fetch!(resume_tokens, p1), %{
        round_count: 1,
        turn_length: 30
      })

    words_by_player =
      play_turn(room_id, p1, p1_token, p2, p2_token, [
        %{
          "event_type" => "start",
          "x" => 10,
          "y" => 20,
          "color" => "#000000",
          "line_width" => 9
        }
      ])
      |> then(&%{p1 => &1})

    words_by_player =
      Map.put(words_by_player, p2, play_turn(room_id, p1, p1_token, p2, p2_token, []))

    {:ok, snapshot} = snapshot_as(room_id, p1_token)

    winner_id =
      Enum.max_by(snapshot.player_order, fn pid -> Map.fetch!(snapshot.players, pid).score end)

    winner = Map.fetch!(snapshot.players, winner_id)
    winner_word = Map.get(words_by_player, winner_id)

    html = render(view)

    assert html =~ "Game finished"
    assert html =~ winner.name
    assert html =~ "aria-label=\"Round 1\""
    assert html =~ winner_word
    assert html =~ "data-final-drawing-events="
    assert html =~ "data-final-drawing-replay=\"true\""
    assert html =~ "data-drawing-share-url="
    assert html =~ "/drawing#"

    [_, share_url] = Regex.run(~r/data-drawing-share-url="([^"]+)"/, html)
    encoded = share_url |> String.split("/drawing#") |> List.last()

    assert {:ok,
            %{
              drawer_name: drawer_name,
              word: ^winner_word
            }} = DrawingShare.decode(encoded)

    assert drawer_name == winner.name
  end

  test "final score rows select the drawing showcase", %{
    conn: conn,
    room_id: room_id
  } do
    {:ok, p1_token, %{viewer_id: p1}} = join_connected(room_id, "Alice")
    {:ok, p2_token, %{viewer_id: p2}} = join_connected(room_id, "Bob")

    {:ok, view, _html} = live(conn, ~p"/game/#{room_id}?resume_token=#{p1_token}")

    resume_tokens = %{p1 => p1_token, p2 => p2_token}

    :ok =
      start_game_as(room_id, Map.fetch!(resume_tokens, p1), %{
        round_count: 1,
        turn_length: 30
      })

    alice_word =
      play_turn(room_id, p1, p1_token, p2, p2_token, [
        %{
          "event_type" => "start",
          "x" => 10,
          "y" => 20,
          "color" => "#000000",
          "line_width" => 9
        }
      ])

    bob_word =
      play_turn(room_id, p1, p1_token, p2, p2_token, [
        %{
          "event_type" => "start",
          "x" => 30,
          "y" => 40,
          "color" => "#EF120B",
          "line_width" => 9
        }
      ])

    html = render(view)
    assert html =~ alice_word
    assert html =~ "final-drawing-#{p1}-round-1"

    html =
      view
      |> element("[data-player-id='#{p2}']")
      |> render_click()

    assert html =~ bob_word
    assert html =~ "final-drawing-#{p2}-round-1"
    assert html =~ "data-selected=\"true\""
  end

  test "selected final score row has a client-side replay control", %{
    conn: conn,
    room_id: room_id
  } do
    {:ok, p1_token, %{viewer_id: p1}} = join_connected(room_id, "Alice")
    {:ok, p2_token, %{viewer_id: p2}} = join_connected(room_id, "Bob")

    {:ok, view, _html} = live(conn, ~p"/game/#{room_id}?resume_token=#{p1_token}")

    resume_tokens = %{p1 => p1_token, p2 => p2_token}

    :ok =
      start_game_as(room_id, Map.fetch!(resume_tokens, p1), %{
        round_count: 1,
        turn_length: 30
      })

    play_turn(room_id, p1, p1_token, p2, p2_token, [])
    play_turn(room_id, p1, p1_token, p2, p2_token, [])

    html = render(view)

    assert html =~ "aria-label=\"Replay selected drawings\""
    assert html =~ "data-replay-final-drawings"
    refute html =~ "phx-click=\"replay_final_drawings\""
  end

  test "final score row with an empty drawing remains selectable", %{
    conn: conn,
    room_id: room_id
  } do
    {:ok, p1_token, %{viewer_id: p1}} = join_connected(room_id, "Alice")
    {:ok, p2_token, %{viewer_id: p2}} = join_connected(room_id, "Bob")

    {:ok, view, _html} = live(conn, ~p"/game/#{room_id}?resume_token=#{p1_token}")

    :ok = start_game_as(room_id, p1_token, %{round_count: 1, turn_length: 30})

    play_turn(room_id, p1, p1_token, p2, p2_token)
    play_turn(room_id, p1, p1_token, p2, p2_token)

    html =
      view
      |> element("[data-player-id='#{p2}']")
      |> render_click()

    assert html =~ "Bob"
    assert html =~ "aria-label=\"Round 1\""
    assert html =~ "data-selected=\"true\""
  end

  test "pushes round audio lifecycle events as phases change", %{conn: conn, room_id: room_id} do
    {:ok, p1_token, %{viewer_id: p1}} = join_connected(room_id, "Alice")
    {:ok, p2_token, %{viewer_id: p2}} = join_connected(room_id, "Bob")

    {:ok, view, _html} = live(conn, ~p"/game/#{room_id}?resume_token=#{p1_token}")

    resume_tokens = %{p1 => p1_token, p2 => p2_token}

    :ok =
      start_game_as(room_id, Map.fetch!(resume_tokens, p1), %{
        round_count: 1,
        turn_length: 30
      })

    assert_push_event(view, "sync_round_audio", %{
      phase: "word_choice",
      end_time: word_choice_end_time
    })

    assert is_binary(word_choice_end_time)
    assert_push_event(view, "set_timer", %{end_time: ^word_choice_end_time})

    {:ok, state} = RoomServer.get_state(room_id)
    word = List.first(state.game.word_choices)

    :ok =
      select_word_as(
        room_id,
        if(state.game.drawer_id == p1, do: p1_token, else: p2_token),
        word
      )

    assert_push_event(view, "sync_round_audio", %{
      phase: "playing",
      end_time: playing_end_time
    })

    assert is_binary(playing_end_time)
    assert_push_event(view, "set_timer", %{end_time: ^playing_end_time})

    {:ok, state} = RoomServer.get_state(room_id)
    drawer_token = if(state.game.drawer_id == p1, do: p1_token, else: p2_token)
    draw_event_as(room_id, drawer_token, %{"event_type" => "clear"})
    _ = :sys.get_state(RoomServer.whereis(room_id))
    refute_push_event(view, "set_timer", %{})

    guesser = if(p1 == state.game.drawer_id, do: p2, else: p1)
    :correct = guess_as(room_id, if(guesser == p1, do: p1_token, else: p2_token), word)

    assert_push_event(view, "sync_round_audio", %{
      phase: "turn_reveal",
      end_time: reveal_end_time
    })

    assert is_binary(reveal_end_time)
  end

  defp play_turn(room_id, p1, p1_token, p2, p2_token, drawing_events \\ []) do
    {:ok, state} = RoomServer.get_state(room_id)
    word = List.first(state.game.word_choices)

    :ok =
      select_word_as(
        room_id,
        if(state.game.drawer_id == p1, do: p1_token, else: p2_token),
        word
      )

    {:ok, state} = RoomServer.get_state(room_id)

    Enum.each(
      drawing_events,
      &draw_event_as(room_id, if(state.game.drawer_id == p1, do: p1_token, else: p2_token), &1)
    )

    guesser = if(p1 == state.game.drawer_id, do: p2, else: p1)
    :correct = guess_as(room_id, if(guesser == p1, do: p1_token, else: p2_token), word)

    pid = RoomServer.whereis(room_id)
    _ = :sys.get_state(pid)

    {:ok, state} = RoomServer.get_state(room_id)
    send(pid, {:game_timeout, :phase, :turn_reveal, state.phase_timer.generation})
    _ = :sys.get_state(pid)

    word
  end
end
