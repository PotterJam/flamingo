defmodule Flamingo.GameHistoryTest do
  # The room and the task that records its games use the shared sandbox.
  use Flamingo.DataCase, async: false

  import Flamingo.AccountsFixtures

  alias Flamingo.{Accounts, DrawingShare, GameHistory, Rooms, RoomSupervisor, SavedLobbies}

  alias Flamingo.GameHistory.{
    GameResult,
    GameResultPlayer,
    ScribbleDrawing,
    ScribbleResult,
    SpellslingersResult
  }

  @stroke [
    %{"event_type" => "start", "x" => 10, "y" => 20, "color" => "#000000", "line_width" => 9},
    %{
      "event_type" => "draw",
      "start_x" => 10,
      "start_y" => 20,
      "end_x" => 60,
      "end_y" => 80,
      "color" => "#000000",
      "line_width" => 9
    }
  ]

  defp start_room do
    room_id = "history-#{System.unique_integer([:positive])}"
    {:ok, ^room_id} = RoomSupervisor.start_room(room_id)
    room_id
  end

  # A connected player in its own process, which runs operations on request.
  defp player(room_id, name, user_id \\ nil) do
    parent = self()

    pid =
      start_supervised!(
        Supervisor.child_spec(
          {Task,
           fn ->
             {:ok, token, _} = Rooms.join(room_id, name, Flamingo.Avatar.default(), user_id)
             {:ok, snapshot} = Rooms.connect(room_id, token)
             send(parent, {:joined, self(), snapshot.viewer_id})
             player_loop()
           end},
          id: {:player, name}
        )
      )

    assert_receive {:joined, ^pid, seat_id}
    %{pid: pid, seat_id: seat_id}
  end

  defp player_loop do
    receive do
      {:run, caller, ref, fun} ->
        send(caller, {ref, fun.()})
        player_loop()

      _snapshot ->
        player_loop()
    end
  end

  defp as(%{pid: pid}, fun) do
    ref = make_ref()
    send(pid, {:run, self(), ref, fun})
    # Starting a Spellslingers duel generates its map, which can take a while.
    assert_receive {^ref, result}, 5_000
    result
  end

  defp room_state(room_id), do: :sys.get_state(:global.whereis_name({:flamingo_room, room_id}))

  defp fire_phase_timeout(room_id) do
    %{phase_timer: timer} = room_state(room_id)

    send(
      :global.whereis_name({:flamingo_room, room_id}),
      {:game_timeout, :phase, timer.key, timer.generation}
    )

    room_state(room_id)
  end

  defp finish_turn(room_id) do
    if room_state(room_id).game.phase in [:playing, :turn_reveal] do
      fire_phase_timeout(room_id)
      finish_turn(room_id)
    end
  end

  # Draws a stroke, lets the guesser get it, and moves past the reveal.
  defp play_turn(room_id, drawer, guesser) do
    {:ok, %{word_choices: [word | _]}} = as(drawer, fn -> Rooms.snapshot(room_id) end)
    :ok = as(drawer, fn -> Rooms.select_word(room_id, word) end)
    as(drawer, fn -> Enum.each(@stroke, &Rooms.draw_event(room_id, &1)) end)
    :correct = as(guesser, fn -> Rooms.guess(room_id, word) end)
    finish_turn(room_id)
    word
  end

  defp await_recordings do
    for pid <- Task.Supervisor.children(Flamingo.TaskSupervisor) do
      ref = Process.monitor(pid)
      assert_receive {:DOWN, ^ref, :process, ^pid, _}, 5_000
    end
  end

  defp play_saved_game(alice_user, opts \\ []) do
    room_id = start_room()
    alice = player(room_id, "Alice", alice_user.id)
    bob = player(room_id, "Bob")
    cara = if opts[:leaver], do: player(room_id, "Cara")
    name = "crew-#{System.unique_integer([:positive])}"

    {:ok, saved_lobby} =
      as(alice, fn ->
        SavedLobbies.save_room(Accounts.Scope.for_user(alice_user), room_id, %{name: name})
      end)

    :ok = as(alice, fn -> Flamingo.TestGames.start_game(room_id, %{round_count: 1}) end)
    first = play_turn(room_id, alice, bob)
    if cara, do: as(cara, fn -> Rooms.leave(room_id) end)
    second = play_turn(room_id, bob, alice)
    assert {:finished, _} = room_state(room_id).lifecycle
    await_recordings()

    %{saved_lobby: saved_lobby, words: [first, second], alice: alice, bob: bob, cara: cara}
  end

  test "a finished saved lobby game records players, scores, placings and drawings" do
    user = user_fixture()
    %{saved_lobby: saved_lobby, words: [first, second]} = play_saved_game(user, leaver: true)

    game = Repo.get_by!(GameResult, saved_lobby_id: saved_lobby.id)
    assert %{mode: :classic} = game
    assert %{round_count: 1} = Repo.get_by!(ScribbleResult, game_result_id: game.id)

    players =
      Repo.all(from p in GameResultPlayer, where: p.game_result_id == ^game.id)
      |> Map.new(&{&1.name, &1})

    # Each guessed once and drew once with one correct guess, so they tie for
    # the win. Cara left mid-game: she stays in the game unranked.
    assert %{user_id: user_id, placement: 1, score: 500} = players["Alice"]
    assert user_id == user.id
    assert %{user_id: nil, placement: 1, score: 500} = players["Bob"]
    assert %{user_id: nil, placement: nil, score: 0} = players["Cara"]

    drawings =
      Repo.all(from d in ScribbleDrawing, where: d.game_result_id == ^game.id, order_by: d.turn)

    assert [{1, ^first, alice_id}, {2, ^second, bob_id}] =
             Enum.map(drawings, &{&1.turn, &1.word, &1.drawer_id})

    assert alice_id == players["Alice"].id and bob_id == players["Bob"].id

    assert {:ok, %{drawer_name: "Alice", word: ^first, events: [_ | _]}} =
             DrawingShare.decode(hd(drawings).payload)

    assert {:ok, [["p", "#000000", 9, _] | _]} = DrawingShare.decode_ops(hd(drawings).payload)
    assert {:error, :invalid_drawing} = DrawingShare.decode_ops("not-valid")

    assert [%{id: listed_id}] = GameHistory.list_games(saved_lobby.id, mode: :classic)
    assert listed_id == game.id

    assert GameHistory.list_games(saved_lobby.id, mode: :spellslingers) == []
    assert GameHistory.count_games(saved_lobby.id) == 1
    assert GameHistory.count_games(saved_lobby.id, mode: :classic) == 1
    assert GameHistory.count_games(saved_lobby.id, mode: :coop) == 0

    loaded = GameHistory.get_game(saved_lobby.id, game.id)
    assert loaded.scribble_result.round_count == 1

    assert Enum.map(loaded.players, &{&1.name, &1.placement}) == [
             {"Alice", 1},
             {"Bob", 1},
             {"Cara", nil}
           ]

    assert length(loaded.drawings) == 2

    assert GameHistory.get_game(saved_lobby.id, "not-a-uuid") == nil
    assert GameHistory.get_game(Ecto.UUID.generate(), game.id) == nil
  end

  test "standings count wins for signed-in players only, keeping deleted accounts' games" do
    user = user_fixture()
    %{saved_lobby: saved_lobby} = play_saved_game(user)

    assert [%{user_id: user_id, name: "Alice", wins: 1, played: 1}] =
             GameHistory.standings(saved_lobby.id)

    assert user_id == user.id

    GameHistory.forget_user(user.id)
    assert GameHistory.standings(saved_lobby.id) == []
    assert Repo.aggregate(GameResultPlayer, :count) == 2
    assert Repo.get_by(GameResultPlayer, name: "Former player")
  end

  test "a Spellslingers duel in a saved lobby is recorded without drawings" do
    user = user_fixture()
    room_id = start_room()
    alice = player(room_id, "Alice", user.id)
    bob = player(room_id, "Bob")
    cara = player(room_id, "Cara")

    {:ok, saved_lobby} =
      as(alice, fn ->
        SavedLobbies.save_room(Accounts.Scope.for_user(user), room_id, %{
          name: "duel-#{System.unique_integer([:positive])}"
        })
      end)

    :ok =
      as(alice, fn -> Flamingo.TestGames.start_game(room_id, %{game_mode: :spellslingers}) end)

    as(cara, fn -> Rooms.leave(room_id) end)
    as(bob, fn -> Rooms.leave(room_id) end)
    assert {:finished, _} = room_state(room_id).lifecycle
    await_recordings()

    game = Repo.get_by!(GameResult, saved_lobby_id: saved_lobby.id)
    assert %{mode: :spellslingers} = game
    assert %{map: map} = Repo.get_by!(SpellslingersResult, game_result_id: game.id)
    assert is_binary(map)

    players =
      Repo.all(
        from p in GameResultPlayer,
          where: p.game_result_id == ^game.id,
          select: {p.name, p.placement}
      )

    assert Enum.sort(players) == [{"Alice", 1}, {"Bob", nil}, {"Cara", nil}]
    assert Repo.aggregate(ScribbleDrawing, :count) == 0
    assert [%{name: "Alice", wins: 1}] = GameHistory.standings(saved_lobby.id)
  end

  test "games in quick rooms are not recorded" do
    room_id = start_room()
    alice = player(room_id, "Alice", user_fixture().id)
    bob = player(room_id, "Bob")
    :ok = as(alice, fn -> Flamingo.TestGames.start_game(room_id, %{round_count: 1}) end)
    play_turn(room_id, alice, bob)
    play_turn(room_id, bob, alice)
    assert {:finished, _} = room_state(room_id).lifecycle
    await_recordings()

    assert Repo.aggregate(GameResult, :count) == 0
  end

  test "placings are shared by tied scores" do
    assert GameHistory.placements(%{"a" => 400, "b" => 400, "c" => 100, "d" => 700}) ==
             %{"d" => 1, "a" => 2, "b" => 2, "c" => 4}
  end

  test "a signed-in player who joins twice keeps one seat; guests get a seat each" do
    room_id = start_room()

    {:ok, token, %{viewer_id: seat}} =
      Rooms.join(room_id, "Alice", Flamingo.Avatar.default(), "user-1")

    assert {:ok, ^token, %{viewer_id: ^seat}} =
             Rooms.join(room_id, "Al", Flamingo.Avatar.default(), "user-1")

    {:ok, other, _} = Rooms.join(room_id, "Bob", Flamingo.Avatar.default(), "user-2")
    {:ok, guest_a, _} = Rooms.join(room_id, "Guest")
    {:ok, guest_b, _} = Rooms.join(room_id, "Guest")
    assert length(Enum.uniq([token, other, guest_a, guest_b])) == 4
  end
end
