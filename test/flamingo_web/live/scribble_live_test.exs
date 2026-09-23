defmodule FlamingoWeb.ScribbleLiveTest do
  use FlamingoWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Flamingo.DrawingShare
  alias Flamingo.Rooms

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
    {:ok, resume_token, _snapshot} = Rooms.join(room_id, player_name)
    {:ok, snapshot} = Rooms.connect(room_id, resume_token)
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
    do: as_player(token, fn -> Rooms.start_game(room_id, settings) end)

  defp select_word_as(room_id, token, word),
    do: as_player(token, fn -> Rooms.select_word(room_id, word) end)

  defp guess_as(room_id, token, guess),
    do: as_player(token, fn -> Rooms.guess(room_id, guess) end)

  defp draw_event_as(room_id, token, event),
    do: as_player(token, fn -> Rooms.draw_event(room_id, event) end)

  defp snapshot_as(room_id, token),
    do: as_player(token, fn -> Rooms.snapshot(room_id) end)

  defp leave_as(room_id, token), do: as_player(token, fn -> Rooms.leave(room_id) end)

  defp room_snapshot(room_id) do
    snapshots =
      for {{:player, token}, _pid} <- Process.get() do
        {:ok, snapshot} = snapshot_as(room_id, token)
        snapshot
      end

    {:ok, Enum.find(snapshots, List.first(snapshots), &(&1.word_choices != []))}
  end

  defp room_pid(room_id), do: :global.whereis_name({:flamingo_room, room_id})

  defp enter_scribble(conn, lobby, room_id, token) do
    path = ~p"/game/#{room_id}/scribble?resume_token=#{token}"
    assert_redirect(lobby, path)
    {:ok, view, _html} = live(conn, path)
    view
  end

  defp finish_reveal(room_id) do
    pid = room_pid(room_id)
    state = :sys.get_state(pid)
    send(pid, {:game_timeout, :phase, :turn_reveal, state.phase_timer.generation})
    _ = :sys.get_state(pid)
  end

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

    view
    |> element("#settings-form")
    |> render_change(%{"settings" => %{"round_count" => "3", "turn_length" => "14"}})

    assert has_element?(view, "#round-length-input[value='15']")

    view
    |> element("#settings-form")
    |> render_change(%{"settings" => %{"round_count" => "3", "turn_length" => "121"}})

    assert has_element?(view, "#round-length-input[value='120']")
  end

  test "host can select custom words and keeps the draft when changing themes", %{
    conn: conn,
    room_id: room_id
  } do
    {:ok, p1_token, _p1_snapshot} = join_connected(room_id, "Alice")
    {:ok, _p2_token, _p2_snapshot} = join_connected(room_id, "Bob")

    {:ok, view, _html} = live(conn, ~p"/game/#{room_id}?resume_token=#{p1_token}")

    refute has_element?(view, "#custom-words-settings")

    view
    |> element("#settings-form")
    |> render_change(%{
      "settings" => %{
        "round_count" => "3",
        "turn_length" => "45",
        "word_list" => "custom",
        "custom_words" => "orbital llama\nvelvet cactus\ndisco teapot"
      }
    })

    assert has_element?(view, "#custom-words-settings")
    assert has_element?(view, "#custom-word-count", "3 / 3000")

    view
    |> element("#settings-form")
    |> render_change(%{
      "settings" => %{
        "round_count" => "3",
        "turn_length" => "45",
        "word_list" => "films"
      }
    })

    refute has_element?(view, "#custom-words-settings")

    view
    |> element("#settings-form")
    |> render_change(%{
      "settings" => %{
        "round_count" => "3",
        "turn_length" => "45",
        "word_list" => "custom"
      }
    })

    custom_words_input =
      view
      |> render()
      |> LazyHTML.from_fragment()
      |> LazyHTML.query("#custom-words-input")

    assert LazyHTML.text(custom_words_input) =~ "orbital llama"
    assert LazyHTML.text(custom_words_input) =~ "velvet cactus"
    assert LazyHTML.text(custom_words_input) =~ "disco teapot"

    view
    |> form("#settings-form", %{
      "settings" => %{
        "round_count" => "3",
        "turn_length" => "45",
        "word_list" => "custom",
        "custom_words" => "orbital llama\nvelvet cactus\ndisco teapot"
      }
    })
    |> render_submit()

    {:ok, state} = room_snapshot(room_id)
    assert state.word_list == :custom
    assert state.custom_words == ["orbital llama", "velvet cactus", "disco teapot"]

    assert Enum.sort(state.word_choices) ==
             Enum.sort(["orbital llama", "velvet cactus", "disco teapot"])

    refute state.include_default_words
  end

  test "host can start with the films word theme", %{conn: conn, room_id: room_id} do
    {:ok, p1_token, _p1_snapshot} = join_connected(room_id, "Alice")
    {:ok, _p2_token, _p2_snapshot} = join_connected(room_id, "Bob")

    {:ok, view, _html} = live(conn, ~p"/game/#{room_id}?resume_token=#{p1_token}")

    view
    |> element("#settings-form")
    |> render_change(%{
      "settings" => %{
        "round_count" => "3",
        "turn_length" => "45",
        "word_list" => "films"
      }
    })

    assert has_element?(view, "#word-list-select option[value='films'][selected]")
    refute has_element?(view, "#word-list-description")
    refute has_element?(view, "#custom-words-settings")

    view
    |> form("#settings-form", %{
      "settings" => %{
        "round_count" => "3",
        "turn_length" => "45",
        "word_list" => "films"
      }
    })
    |> render_submit()

    {:ok, state} = room_snapshot(room_id)
    film_words = File.read!("priv/words/films.txt") |> String.split("\n", trim: true)

    assert state.word_list == :films
    assert state.custom_words == []
    assert Enum.all?(state.word_choices, &(&1 in film_words))
  end

  test "host can start constraint roulette", %{conn: conn, room_id: room_id} do
    {:ok, p1_token, _p1_snapshot} = join_connected(room_id, "Alice")
    {:ok, _p2_token, _p2_snapshot} = join_connected(room_id, "Bob")

    {:ok, view, _html} = live(conn, ~p"/game/#{room_id}?resume_token=#{p1_token}")

    assert has_element?(view, "#game-mode-classic[aria-checked='true']")
    view |> element("#game-mode-constraint_roulette") |> render_click()

    view
    |> form("#settings-form", %{
      "settings" => %{
        "round_count" => "1",
        "turn_length" => "30"
      }
    })
    |> render_submit()

    {:ok, state} = room_snapshot(room_id)
    assert state.game_variant == :constraint_roulette

    assert state.constraint in [
             :hidden_canvas,
             :single_stroke,
             :straight_lines,
             :rotating_canvas,
             :mirror
           ]

    view = enter_scribble(conn, view, room_id, p1_token)

    view
    |> element("button[phx-click='select_word']", List.first(state.word_choices))
    |> render_click()

    assert has_element?(view, "#constraint-banner")
    assert has_element?(view, "#drawing-canvas[data-constraint]")
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
        "word_list" => "custom",
        "custom_words" => "cat, dog"
      }
    })

    assert has_element?(view, "#custom-words-error")

    view
    |> form("#settings-form", %{
      "settings" => %{
        "round_count" => "3",
        "turn_length" => "45",
        "word_list" => "custom",
        "custom_words" => ""
      }
    })
    |> render_submit()

    assert has_element?(view, "#custom-words-error", "Add at least one custom word.")
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
        "word_list" => "custom",
        "custom_words" => "saved locally"
      }
    })

    {:ok, _bob_token, _snapshot} = join_connected(room_id, "Bob")

    assert has_element?(view, "#round-count-slider[value='5']")
    assert has_element?(view, "#round-length-input[value='90']")
    assert has_element?(view, "#word-list-select option[value='custom'][selected]")
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

    drawer_view = enter_scribble(conn, drawer_view, room_id, drawer_id_token)
    guesser_view = enter_scribble(conn, guesser_view, room_id, guesser_id_token)

    {:ok, state} = room_snapshot(room_id)
    word = List.first(state.word_choices)
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

    drawer_view = enter_scribble(conn, drawer_view, room_id, drawer_token)
    duplicate_view = enter_scribble(conn, duplicate_view, room_id, drawer_token)
    guesser_view = enter_scribble(conn, guesser_view, room_id, guesser_token)

    {:ok, state} = room_snapshot(room_id)
    word = List.first(state.word_choices)
    :ok = select_word_as(room_id, drawer_token, word)

    assert_push_event(drawer_view, "drawing_state", %{events: []})
    assert_push_event(duplicate_view, "drawing_state", %{events: []})
    assert_push_event(guesser_view, "drawing_state", %{events: []})

    event = %{"event_type" => "clear"}
    render_hook(drawer_view, "draw_event", event)
    _ = :sys.get_state(room_pid(room_id))

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

    {:ok, state} = room_snapshot(room_id)
    assert state.current_drawing == [event]
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

    {:ok, state} = room_snapshot(room_id)
    :ok = select_word_as(room_id, drawer_token, List.first(state.word_choices))

    first_event = %{"event_type" => "clear"}
    second_event = %{"event_type" => "fill", "x" => 10, "y" => 20, "color" => "#000000"}
    draw_event_as(room_id, drawer_token, first_event)
    draw_event_as(room_id, drawer_token, second_event)
    _ = :sys.get_state(room_pid(room_id))

    {:ok, guesser_view, _html} =
      live(conn, ~p"/game/#{room_id}/scribble?resume_token=#{guesser_token}")

    assert_push_event(guesser_view, "drawing_state", %{events: [^first_event, ^second_event]})
  end

  test "a spectator joining during turn reveal receives the drawing baseline", %{
    conn: conn,
    room_id: room_id
  } do
    {:ok, drawer_token, _drawer_snapshot} = join_connected(room_id, "Alice")
    {:ok, guesser_token, _guesser_snapshot} = join_connected(room_id, "Bob")

    :ok =
      start_game_as(room_id, drawer_token, %{
        custom_words: ["secret", "other", "third"]
      })

    {:ok, state} = room_snapshot(room_id)
    word = List.first(state.word_choices)
    :ok = select_word_as(room_id, drawer_token, word)

    event = %{"event_type" => "clear"}
    draw_event_as(room_id, drawer_token, event)
    _ = :sys.get_state(room_pid(room_id))
    assert :correct = guess_as(room_id, guesser_token, word)

    {:ok, spectator_token, %{participation: :spectator}} =
      Rooms.join(room_id, "Charlie")

    {:ok, spectator_view, _html} =
      live(conn, ~p"/game/#{room_id}/scribble?resume_token=#{spectator_token}")

    assert_push_event(spectator_view, "drawing_state", %{events: [^event]})
    assert has_element?(spectator_view, "#spectator-notice")
    refute has_element?(spectator_view, "#guess-form")
  end

  test "hidden canvas is revealed to the drawer during turn reveal", %{
    conn: conn,
    room_id: room_id
  } do
    {:ok, drawer_token, _drawer_snapshot} = join_connected(room_id, "Alice")
    {:ok, guesser_token, _guesser_snapshot} = join_connected(room_id, "Bob")

    :ok =
      start_game_as(room_id, drawer_token, %{
        game_variant: :constraint_roulette,
        custom_words: ["secret", "other", "third"]
      })

    {:ok, state} = room_snapshot(room_id)
    :sys.replace_state(room_pid(room_id), &put_in(&1.game.constraint, :hidden_canvas))

    {:ok, drawer_view, _html} =
      live(conn, ~p"/game/#{room_id}/scribble?resume_token=#{drawer_token}")

    :ok = select_word_as(room_id, drawer_token, List.first(state.word_choices))

    assert has_element?(
             drawer_view,
             "#drawing-canvas[data-is-drawer='true'][data-constraint='hidden_canvas'][data-phase='playing']"
           )

    assert :correct = guess_as(room_id, guesser_token, List.first(state.word_choices))

    assert has_element?(
             drawer_view,
             "#drawing-canvas[data-is-drawer='true'][data-constraint='hidden_canvas'][data-phase='turn_reveal']"
           )
  end

  test "a late joiner spectates until the next turn", %{conn: conn, room_id: room_id} do
    {:ok, drawer_token, %{viewer_id: drawer}} = join_connected(room_id, "Alice")
    {:ok, guesser_token, %{viewer_id: guesser}} = join_connected(room_id, "Bob")

    :ok =
      start_game_as(room_id, drawer_token, %{
        round_count: 1,
        custom_words: ["secret", "other", "third"]
      })

    {:ok, state} = room_snapshot(room_id)
    word = List.first(state.word_choices)
    assert state.drawer_id == drawer
    :ok = select_word_as(room_id, drawer_token, word)

    event = %{"event_type" => "clear"}
    draw_event_as(room_id, drawer_token, event)
    _ = :sys.get_state(room_pid(room_id))

    {:ok, spectator_token, %{participation: :spectator}} =
      Rooms.join(room_id, "Charlie")

    {:ok, spectator_view, _html} =
      live(conn, ~p"/game/#{room_id}/scribble?resume_token=#{spectator_token}")

    assert_push_event(spectator_view, "drawing_state", %{events: [^event]})
    assert has_element?(spectator_view, "#spectator-notice")
    assert has_element?(spectator_view, "#drawing-canvas[data-is-drawer='false']")
    refute has_element?(spectator_view, "#guess-form")
    refute has_element?(spectator_view, "#drawing-canvas [data-action='undo']")

    assert :correct = guess_as(room_id, guesser_token, word)
    finish_reveal(room_id)

    {:ok, state} = room_snapshot(room_id)
    assert state.drawer_id == guesser
    assert Map.fetch!(state.players, state.viewer_id).connected

    :ok =
      select_word_as(room_id, guesser_token, List.first(state.word_choices))

    refute has_element?(spectator_view, "#spectator-notice")
    assert has_element?(spectator_view, "#guess-form")
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

    view = enter_scribble(conn, view, room_id, p1_token)

    play_turn(room_id, p1, p1_token, p2, p2_token)
    play_turn(room_id, p1, p1_token, p2, p2_token)

    html = render(view)
    assert has_element?(view, "#final-leaderboard h2", "Results")
    assert html =~ "Alice"
    assert html =~ "Bob"

    :ok = leave_as(room_id, Map.fetch!(resume_tokens, p2))

    html = render(view)
    assert has_element?(view, "#final-leaderboard h2", "Results")
    assert html =~ "Alice"
    assert html =~ "Bob"

    {:ok, snapshot} = snapshot_as(room_id, p1_token)
    refute Map.has_key?(snapshot.players, p2)
    assert snapshot.final_player_order == [p1, p2]
    assert Map.fetch!(snapshot.final_players, p1).score > 0
    assert Map.fetch!(snapshot.final_players, p2).score > 0

    {:ok, reconnected_view, _html} =
      live(conn, ~p"/game/#{room_id}/scribble?resume_token=#{p1_token}")

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

    view = enter_scribble(conn, view, room_id, p1_token)

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

    assert has_element?(view, "#final-leaderboard h2", "Results")
    assert html =~ winner.name
    assert has_element?(view, "#previous-final-drawing[disabled]")
    assert has_element?(view, "#next-final-drawing[disabled]")
    assert html =~ winner_word
    assert html =~ "data-final-drawing-events="
    assert html =~ "data-final-drawing-replay=\"true\""
    assert html =~ "data-drawing-share-url="
    assert html =~ "/drawing#"
    refute html =~ "final-drawing-constraint-"

    [_, share_url] = Regex.run(~r/data-drawing-share-url="([^"]+)"/, html)
    encoded = share_url |> String.split("/drawing#") |> List.last()

    assert {:ok,
            %{
              drawer_name: drawer_name,
              word: ^winner_word
            }} = DrawingShare.decode(encoded)

    assert drawer_name == winner.name
  end

  test "final score rows switch between populated and empty drawings", %{
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

    view = enter_scribble(conn, view, room_id, p1_token)

    play_turn(room_id, p1, p1_token, p2, p2_token, [
      %{
        "event_type" => "start",
        "x" => 10,
        "y" => 20,
        "color" => "#000000",
        "line_width" => 9
      }
    ])

    play_turn(room_id, p1, p1_token, p2, p2_token, [])

    assert has_element?(view, "#final-score-row-#{p1} [data-selected='true']")
    assert has_element?(view, "#final-drawing-#{p1}-round-1")
    refute has_element?(view, "#final-drawing-#{p2}-round-1")

    assert has_element?(view, "#final-leaderboard #final-score-rows")
    assert has_element?(view, "#final-leaderboard #return-to-lobby")
    assert has_element?(view, "#final-drawings #final-drawing-#{p1}-round-1")

    view |> element("#final-score-row-#{p2} [data-player-id]") |> render_click()

    assert has_element?(view, "#final-score-row-#{p2} [data-selected='true']")
    assert has_element?(view, "#final-score-row-#{p1} [data-selected='false']")
    assert has_element?(view, "#final-drawing-#{p2}-round-1[data-final-drawing-events='[]']")
    refute has_element?(view, "#final-drawing-#{p1}-round-1")

    view |> element("#final-score-row-#{p1} [data-player-id]") |> render_click()

    assert has_element?(view, "#final-score-row-#{p1} [data-selected='true']")
    assert has_element?(view, "#final-drawing-#{p1}-round-1")
    refute has_element?(view, "#final-drawing-#{p2}-round-1")

    {:ok, guest_view, _html} =
      live(conn, ~p"/game/#{room_id}/scribble?resume_token=#{p2_token}")

    refute has_element?(guest_view, "#return-to-lobby")

    view |> element("#return-to-lobby") |> render_click()
    assert_redirect(view, ~p"/game/#{room_id}?resume_token=#{p1_token}")
  end

  test "final results preserve each artist's votes in podium and remaining rows", %{
    conn: conn,
    room_id: room_id
  } do
    players =
      for name <- ["Alice", "Bob", "Charlie", "Dana"] do
        {:ok, token, %{viewer_id: id}} = join_connected(room_id, name)
        {id, token}
      end

    [{_, host_token} | _] = players
    tokens = Map.new(players)
    {:ok, lobby, _} = live(conn, ~p"/game/#{room_id}?resume_token=#{host_token}")
    :ok = start_game_as(room_id, host_token, %{round_count: 1, turn_length: 30})
    view = enter_scribble(conn, lobby, room_id, host_token)

    expected =
      for votes <- [[:up, :down, :up], [:down, :down, :down], [], [:up, :up, :up]] do
        {:ok, snapshot} = room_snapshot(room_id)
        artist = snapshot.drawer_id
        word = hd(snapshot.word_choices)
        :ok = select_word_as(room_id, Map.fetch!(tokens, artist), word)
        guessers = Enum.reject(players, fn {id, _} -> id == artist end)

        for {{_, token}, vote} <- Enum.zip(guessers, votes) do
          :ok = as_player(token, fn -> Rooms.command(room_id, {:vote_drawing, vote}) end)
        end

        for {_, token} <- guessers, do: assert(:correct == guess_as(room_id, token, word))
        finish_reveal(room_id)
        {artist, votes}
      end

    assert has_element?(view, "#final-podium [id^='final-votes-']")
    assert has_element?(view, "#final-remaining-players [data-player-id]")

    for {artist, votes} <- expected do
      selector = "#final-score-row-#{artist} #final-votes-#{artist}"

      if votes == [] do
        refute has_element?(view, selector)
      else
        for vote <- [:up, :down] do
          count = Enum.count(votes, &(&1 == vote))

          if count > 0 do
            assert has_element?(view, "#{selector} [aria-label='#{count} thumbs #{vote}']")
          else
            refute has_element?(view, "#{selector} [aria-label$='thumbs #{vote}']")
          end
        end
      end
    end
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

    view = enter_scribble(conn, view, room_id, p1_token)

    assert_push_event(view, "sync_round_audio", %{
      phase: "word_choice",
      end_time: word_choice_end_time
    })

    assert is_binary(word_choice_end_time)
    assert_push_event(view, "set_timer", %{end_time: ^word_choice_end_time})

    {:ok, state} = room_snapshot(room_id)
    word = List.first(state.word_choices)

    :ok =
      select_word_as(
        room_id,
        if(state.drawer_id == p1, do: p1_token, else: p2_token),
        word
      )

    assert_push_event(view, "sync_round_audio", %{
      phase: "playing",
      end_time: playing_end_time
    })

    assert is_binary(playing_end_time)
    assert_push_event(view, "set_timer", %{end_time: ^playing_end_time})

    {:ok, state} = room_snapshot(room_id)
    drawer_token = if(state.drawer_id == p1, do: p1_token, else: p2_token)
    draw_event_as(room_id, drawer_token, %{"event_type" => "clear"})
    _ = :sys.get_state(room_pid(room_id))
    refute_push_event(view, "set_timer", %{})

    guesser = if(p1 == state.drawer_id, do: p2, else: p1)
    :correct = guess_as(room_id, if(guesser == p1, do: p1_token, else: p2_token), word)

    assert_push_event(view, "sync_round_audio", %{
      phase: "turn_reveal",
      end_time: reveal_end_time
    })

    assert is_binary(reveal_end_time)
  end

  defp play_turn(room_id, p1, p1_token, p2, p2_token, drawing_events \\ []) do
    {:ok, state} = room_snapshot(room_id)
    word = List.first(state.word_choices)

    :ok =
      select_word_as(
        room_id,
        if(state.drawer_id == p1, do: p1_token, else: p2_token),
        word
      )

    {:ok, state} = room_snapshot(room_id)

    Enum.each(
      drawing_events,
      &draw_event_as(room_id, if(state.drawer_id == p1, do: p1_token, else: p2_token), &1)
    )

    guesser = if(p1 == state.drawer_id, do: p2, else: p1)
    :correct = guess_as(room_id, if(guesser == p1, do: p1_token, else: p2_token), word)

    finish_reveal(room_id)

    word
  end
end
