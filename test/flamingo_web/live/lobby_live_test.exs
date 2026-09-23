defmodule FlamingoWeb.LobbyLiveTest do
  use FlamingoWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Flamingo.{RoomServer, Rooms}

  setup %{conn: conn} do
    room_id = "lobby-#{System.unique_integer([:positive])}"
    server = start_supervised!({RoomServer, room_id})
    {:ok, token, snapshot} = Rooms.join(room_id, "Alice")
    {:ok, host, _} = live(conn, ~p"/game/#{room_id}?resume_token=#{token}")
    %{room_id: room_id, server: server, token: token, host_id: snapshot.viewer_id, host: host}
  end

  test "edited settings survive a membership update and reach the game", context do
    %{conn: conn, host: host, room_id: room_id, token: token} = context
    host |> element("#game-mode-constraint_roulette") |> render_click()
    host |> form("#settings-form", settings: %{word_list: "custom"}) |> render_change()

    host
    |> form("#settings-form",
      settings: %{
        round_count: "2",
        turn_length: "60",
        word_list: "custom",
        custom_words: "orbital llama\nvelvet cactus\ndisco teapot"
      }
    )
    |> render_change()

    {:ok, guest_token, _} = Rooms.join(room_id, "Bob")
    {:ok, _guest, _} = live(conn, ~p"/game/#{room_id}?resume_token=#{guest_token}")
    host |> form("#settings-form") |> render_submit()

    assert_redirect(host, ~p"/game/#{room_id}/scribble?resume_token=#{token}")
    assert {:ok, snapshot} = Rooms.connect(room_id, token)
    assert snapshot.mode == :scribble
    assert snapshot.game_variant == :constraint_roulette
    assert snapshot.round_count == 2
    assert snapshot.turn_length == 60
    assert snapshot.word_list == :custom
    assert snapshot.custom_words == ["orbital llama", "velvet cactus", "disco teapot"]
  end

  test "a guest's forged start event leaves the room unchanged", context do
    %{conn: conn, room_id: room_id, token: token} = context
    {:ok, guest_token, _} = Rooms.join(room_id, "Bob")
    {:ok, guest, _} = live(conn, ~p"/game/#{room_id}?resume_token=#{guest_token}")
    {:ok, before} = Rooms.connect(room_id, token)

    render_hook(guest, "start_game", %{"settings" => %{"game_mode" => "telephone"}})

    assert {:ok, ^before} = Rooms.snapshot(room_id)
  end

  test "navigation preserves seats and keeps a slow player eligible for the first turn",
       context do
    %{conn: conn, host: host, token: token, room_id: room_id, host_id: host_id, server: server} =
      context

    {:ok, guest_token, %{viewer_id: guest_id}} = Rooms.join(room_id, "Bob")
    {:ok, guest, _} = live(conn, ~p"/game/#{room_id}?resume_token=#{guest_token}")
    {:ok, slow_token, %{viewer_id: slow_id}} = Rooms.join(room_id, "Charlie")
    {:ok, slow, _} = live(conn, ~p"/game/#{room_id}?resume_token=#{slow_token}")
    host |> form("#settings-form") |> render_submit()

    host_path = ~p"/game/#{room_id}/scribble?resume_token=#{token}"
    guest_path = ~p"/game/#{room_id}/scribble?resume_token=#{guest_token}"
    slow_path = ~p"/game/#{room_id}/scribble?resume_token=#{slow_token}"
    assert_redirect(host, host_path)
    assert_redirect(guest, guest_path)
    assert_redirect(slow, slow_path)
    {:ok, game, _} = live(conn, host_path)
    {:ok, guest_game, _} = live(conn, guest_path)

    for path <- [
          ~p"/game/#{room_id}?resume_token=#{token}",
          ~p"/game/#{room_id}/telephone?resume_token=#{token}"
        ] do
      assert {:error, {:live_redirect, %{to: ^host_path, kind: :replace}}} = live(conn, path)
    end

    ref = Process.monitor(game.pid)
    GenServer.stop(game.pid, :normal)
    assert_receive {:DOWN, ^ref, :process, _, :normal}
    {:ok, reconnected, _} = live(conn, host_path)

    # Connection counts aren't exposed by the public snapshot. Neither player has
    # an extra test connection masking a broken LiveView handoff here.
    seats = :sys.get_state(server).members.seats
    assert seats[host_id].connection_count == 1
    assert seats[guest_id].connection_count == 1

    {:ok, snapshot} = Rooms.connect(room_id, token)
    assert snapshot.player_order == [host_id, guest_id, slow_id]
    assert snapshot.host_id == host_id
    assert snapshot.drawer_id == host_id
    assert snapshot.phase == :word_choice

    word = hd(snapshot.word_choices)
    render_hook(reconnected, "select_word", %{"choice" => word})
    render_hook(guest_game, "guess", %{"guess_form" => %{"guess" => word}})
    {:ok, snapshot} = Rooms.snapshot(room_id)
    assert snapshot.phase == :playing

    {:ok, slow_game, _} = live(conn, slow_path)
    render_hook(slow_game, "guess", %{"guess_form" => %{"guess" => word}})
    {:ok, snapshot} = Rooms.snapshot(room_id)
    assert snapshot.phase == :turn_reveal
    assert MapSet.equal?(snapshot.correct_guesses, MapSet.new([guest_id, slow_id]))
  end

  test "finished games return every viewer and stale game URLs to the same lobby", context do
    %{
      conn: conn,
      room_id: room_id,
      token: token,
      server: server,
      host: initial_host,
      host_id: host_id
    } = context

    {:ok, guest_token, %{viewer_id: guest_id}} = Rooms.join(room_id, "Bob")
    lobby_path = ~p"/game/#{room_id}?resume_token=#{token}"
    guest_lobby_path = ~p"/game/#{room_id}?resume_token=#{guest_token}"
    {:ok, _guest_lobby, _} = live(conn, guest_lobby_path)

    Enum.reduce([:scribble, :telephone], initial_host, fn mode, host_lobby ->
      host_path = "/game/#{room_id}/#{mode}?resume_token=#{token}"
      guest_path = "/game/#{room_id}/#{mode}?resume_token=#{guest_token}"
      mode_id = if mode == :scribble, do: "classic", else: "telephone"
      host_lobby |> element("#game-mode-#{mode_id}") |> render_click()
      host_lobby |> form("#settings-form", settings: %{round_count: "1"}) |> render_change()
      host_lobby |> form("#settings-form") |> render_submit()
      assert_redirect(host_lobby, host_path)
      {:ok, host, _} = live(conn, host_path)

      # The guest has not followed the return-to-lobby redirect before the next
      # match starts. Its one handoff must keep it eligible, without test tabs.
      assert {:error, {:live_redirect, %{to: ^guest_path, kind: :replace}}} =
               live(conn, guest_lobby_path)

      {:ok, guest, _} = live(conn, guest_path)
      state = :sys.get_state(server)
      assert state.members.seats[host_id].connection_count == 1
      assert state.members.seats[guest_id].connection_count == 1
      assert state.game.participants[guest_id] == :active
      if mode == :telephone, do: assert(guest_id in state.game.player_order)

      for _ <- 1..if(mode == :scribble, do: 6, else: 3) do
        timer = :sys.get_state(server).phase_timer
        send(server, {:game_timeout, :phase, timer.key, timer.generation})
        _ = :sys.get_state(server)
      end

      if mode == :telephone do
        host |> element("#start-telephone-reveal") |> render_click()
        for _ <- 1..6, do: host |> element("#advance-telephone-reveal") |> render_click()
      end

      finished = :sys.get_state(server).game
      assert finished.phase == :game_ended
      render_hook(guest, "return_to_lobby", %{})
      assert :sys.get_state(server).game == finished

      # Reconnect the guest's only connection while results are still held.
      ref = Process.monitor(guest.pid)
      GenServer.stop(guest.pid, :normal)
      assert_receive {:DOWN, ^ref, :process, _, :normal}
      assert :sys.get_state(server).members.seats[guest_id].connection_count == 0

      assert {:error, {:live_redirect, %{to: ^guest_path, kind: :replace}}} =
               live(conn, guest_lobby_path)

      {:ok, guest, _} = live(conn, guest_path)
      assert :sys.get_state(server).game == finished

      ref = Process.monitor(guest.pid)
      host |> element("#return-to-lobby") |> render_click()
      assert_redirect(host, lobby_path)
      assert_redirect(guest, guest_lobby_path)

      # The old view stops, but deliberately delay its replacement until after
      # the next start. This is the vulnerable return -> lobby -> game interval.
      assert_receive {:DOWN, ^ref, :process, _, _reason}
      state = :sys.get_state(server)
      assert state.lifecycle == :lobby
      assert state.members.order == [host_id, guest_id]
      assert state.members.host_id == host_id

      for suffix <- ["scribble", "telephone"], mode == :telephone do
        assert {:error, {:live_redirect, %{to: ^guest_lobby_path, kind: :replace}}} =
                 live(conn, "/game/#{room_id}/#{suffix}?resume_token=#{guest_token}")
      end

      {:ok, returned_host, _} = live(conn, lobby_path)
      returned_host
    end)
  end

  test "game URLs send an unstarted room to its lobby", context do
    %{conn: conn, room_id: room_id, token: token} = context
    lobby_path = ~p"/game/#{room_id}?resume_token=#{token}"

    for suffix <- ["scribble", "telephone"] do
      assert {:error, {:live_redirect, %{to: ^lobby_path, kind: :replace}}} =
               live(conn, "/game/#{room_id}/#{suffix}?resume_token=#{token}")
    end
  end

  test "live snapshots route to the owning game, including results", context do
    %{room_id: room_id, token: token} = context
    socket = %Phoenix.LiveView.Socket{assigns: %{room_id: room_id, resume_token: token}}

    for {view, snapshot, expected_path} <- [
          {FlamingoWeb.ScribbleLive, %{mode: :telephone, phase: :telephone_prompt},
           ~p"/game/#{room_id}/telephone?resume_token=#{token}"},
          {FlamingoWeb.TelephoneLive, %{mode: :scribble, phase: :playing},
           ~p"/game/#{room_id}/scribble?resume_token=#{token}"},
          {FlamingoWeb.LobbyLive, %{mode: :scribble, phase: :game_ended},
           ~p"/game/#{room_id}/scribble?resume_token=#{token}"},
          {FlamingoWeb.LobbyLive, %{mode: :telephone, phase: :game_ended},
           ~p"/game/#{room_id}/telephone?resume_token=#{token}"}
        ] do
      assert {:noreply, redirected} = view.handle_info({:room_snapshot, snapshot}, socket)
      assert {:live, :redirect, %{to: ^expected_path, kind: :replace}} = redirected.redirected
    end
  end
end
