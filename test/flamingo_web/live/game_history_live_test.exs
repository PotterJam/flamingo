defmodule FlamingoWeb.GameHistoryLiveTest do
  use FlamingoWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Flamingo.AccountsFixtures

  alias Flamingo.{Accounts, DrawingShare, GameHistory, Repo}

  alias Flamingo.GameHistory.{
    GameResult,
    GameResultPlayer,
    ScribbleDrawing,
    ScribbleResult,
    SpellslingersResult
  }

  alias Flamingo.SavedLobbies.SavedLobby

  @sample_ops [["p", "#000000", 9, [10, 20, 40, 30]]]

  defp insert_lobby(creator, name \\ nil) do
    Repo.insert!(%SavedLobby{
      name: name || "crew-#{System.unique_integer([:positive])}",
      creator_id: creator.id
    })
  end

  defp insert_scribble_game(lobby, opts) do
    now = Keyword.get(opts, :finished_at, DateTime.utc_now(:second))

    game =
      Repo.insert!(%GameResult{
        saved_lobby_id: lobby.id,
        mode: Keyword.get(opts, :mode, :classic),
        started_at: DateTime.add(now, -300, :second),
        finished_at: now
      })

    Repo.insert!(%ScribbleResult{
      game_result_id: game.id,
      round_count: Keyword.get(opts, :round_count, 2)
    })

    players =
      for p <- Keyword.fetch!(opts, :players), into: %{} do
        row =
          Repo.insert!(%GameResultPlayer{
            game_result_id: game.id,
            user_id: p[:user_id],
            name: p.name,
            placement: p[:placement],
            score: p[:score],
            team: p[:team]
          })

        {p.key, row}
      end

    for {d, turn} <- Enum.with_index(Keyword.get(opts, :drawings, []), 1) do
      drawer = players[d.drawer]

      payload =
        DrawingShare.encode(%{
          drawer_name: d[:payload_name] || drawer.name,
          word: d.word,
          round_number: d.round,
          constraint: d[:constraint],
          ops: @sample_ops
        })

      Repo.insert!(%ScribbleDrawing{
        id: Ecto.UUID.generate(),
        game_result_id: game.id,
        drawer_id: drawer.id,
        turn: turn,
        round_number: d.round,
        word: d.word,
        constraint: d[:constraint],
        payload: payload,
        thumbs_up: Map.get(d, :up, 0),
        thumbs_down: Map.get(d, :down, 0)
      })
    end

    {game, players}
  end

  test "anyone with the lobby link can view standings, history, and filter by mode", %{conn: conn} do
    sam = user_fixture()
    priya = user_fixture()
    lobby = insert_lobby(sam)
    now = DateTime.utc_now(:second)

    {classic, _} =
      insert_scribble_game(lobby,
        mode: :classic,
        round_count: 3,
        finished_at: now,
        players: [
          %{key: :sam, user_id: sam.id, name: "Sam", placement: 1, score: 900},
          %{key: :guest, user_id: nil, name: "GuestBob", placement: 2, score: 400}
        ]
      )

    spells =
      Repo.insert!(%GameResult{
        saved_lobby_id: lobby.id,
        mode: :spellslingers,
        started_at: DateTime.add(now, -900, :second),
        finished_at: DateTime.add(now, -600, :second)
      })

    Repo.insert!(%SpellslingersResult{game_result_id: spells.id, map: "isles"})

    Repo.insert!(%GameResultPlayer{
      game_result_id: spells.id,
      user_id: priya.id,
      name: "Priya",
      placement: 1,
      score: 140
    })

    # Unauthenticated guest can see standings (signed-in only) and recent games on /saved-lobby/:name
    {:ok, home, _} = live(conn, ~p"/saved-lobby/#{lobby.name}")
    assert has_element?(home, "#saved-lobby-standings-table-row-#{sam.id}", "Sam")
    assert has_element?(home, "#saved-lobby-standings-table-row-#{priya.id}", "Priya")
    refute render(home) =~ "GuestBob"
    assert has_element?(home, "#recent-game-#{classic.id}", "Sam")
    assert has_element?(home, "#recent-game-#{classic.id}", "900 pts")
    assert has_element?(home, "#recent-game-#{spells.id}", "Priya")
    assert has_element?(home, "#recent-game-#{spells.id}", "140 dmg")

    # History page filters by mode
    {:ok, history, _} = live(conn, ~p"/saved-lobby/#{lobby.name}/history")
    assert has_element?(history, "#history-game-#{classic.id}")
    assert has_element?(history, "#history-game-#{spells.id}")

    history |> element("#filter-mode-spellslingers") |> render_click()
    refute has_element?(history, "#history-game-#{classic.id}")
    assert has_element?(history, "#history-game-#{spells.id}")
  end

  test "past Classic game shows account avatars only for signed-in players, badges guests/leavers, and hides forgotten names in share links",
       %{conn: conn} do
    sam = user_fixture()
    {:ok, sam} = Accounts.update_avatar(Accounts.Scope.for_user(sam), %{"head" => 3})
    deleted = user_fixture()
    lobby = insert_lobby(sam)

    {game, players} =
      insert_scribble_game(lobby,
        mode: :classic,
        round_count: 2,
        players: [
          %{key: :sam, user_id: sam.id, name: "Sam", placement: 1, score: 1200},
          %{key: :guest, user_id: nil, name: "Tom", placement: 2, score: 640},
          %{key: :deleted, user_id: deleted.id, name: "SecretName", placement: 3, score: 420},
          %{key: :leaver, user_id: nil, name: "Leo", placement: nil, score: 100}
        ],
        drawings: [
          %{drawer: :sam, round: 1, word: "cat", up: 4, down: 0},
          %{drawer: :deleted, round: 1, word: "house", payload_name: "SecretName", up: 2, down: 1}
        ]
      )

    GameHistory.forget_user(deleted.id)

    {:ok, view, _} = live(conn, ~p"/saved-lobby/#{lobby.name}/history/#{game.id}")

    # Signed-in player gets avatar; guest and Former player get no avatar
    assert has_element?(
             view,
             "#game-player-row-#{players.sam.id} svg[aria-label=\"Sam's avatar\"]"
           )

    refute has_element?(view, "#game-player-row-#{players.guest.id} svg[role='img']")
    assert has_element?(view, "#game-player-row-#{players.guest.id}", "Guest")
    assert has_element?(view, "#game-player-row-#{players.deleted.id}", "Former player")
    refute has_element?(view, "#game-player-row-#{players.deleted.id}", "Guest")
    assert has_element?(view, "#game-player-row-#{players.leaver.id}", "Left early")

    # Defaults to winner's drawings; selecting Former player switches drawings and strips old name from share link
    assert has_element?(view, "#game-drawings-heading", "cat")
    assert has_element?(view, "#game-drawings", "Sam")

    view |> element("#game-player-row-#{players.deleted.id} button") |> render_click()
    assert has_element?(view, "#game-drawings-heading", "house")
    assert has_element?(view, "#game-drawings", "Former player")

    share_url =
      view
      |> render()
      |> LazyHTML.from_fragment()
      |> LazyHTML.query("[data-drawing-share-url]")
      |> LazyHTML.attribute("data-drawing-share-url")
      |> hd()

    encoded = share_url |> URI.parse() |> Map.fetch!(:fragment)
    assert {:ok, %{drawer_name: "Former player", word: "house"}} = DrawingShare.decode(encoded)
  end

  test "past Teams and Spellslingers games render mode-specific layouts and scope games to their lobby",
       %{conn: conn} do
    sam = user_fixture()
    priya = user_fixture()
    lobby = insert_lobby(sam)
    other_lobby = insert_lobby(sam)

    {teams_game, _} =
      insert_scribble_game(lobby,
        mode: :coop,
        round_count: 2,
        players: [
          %{key: :sam, user_id: sam.id, name: "Sam", placement: 1, score: 800, team: 1},
          %{key: :priya, user_id: priya.id, name: "Priya", placement: 2, score: 500, team: 2}
        ],
        drawings: [
          %{drawer: :sam, round: 1, word: "rocket"},
          %{drawer: :priya, round: 1, word: "pizza"}
        ]
      )

    {:ok, teams_view, _} = live(conn, ~p"/saved-lobby/#{lobby.name}/history/#{teams_game.id}")
    assert has_element?(teams_view, "#game-team-row-1", "Team 1")
    assert has_element?(teams_view, "#game-drawings-heading", "rocket")

    teams_view |> element("#game-team-row-2 button") |> render_click()
    assert has_element?(teams_view, "#game-drawings-heading", "pizza")

    # Cross-lobby game access redirects to that lobby's history
    assert {:error, {:live_redirect, %{to: redirect_to}}} =
             live(conn, ~p"/saved-lobby/#{other_lobby.name}/history/#{teams_game.id}")

    assert redirect_to == ~p"/saved-lobby/#{other_lobby.name}/history"

    # Spellslingers duel with no survivor
    spells =
      Repo.insert!(%GameResult{
        saved_lobby_id: lobby.id,
        mode: :spellslingers,
        started_at: DateTime.add(DateTime.utc_now(:second), -300, :second),
        finished_at: DateTime.utc_now(:second)
      })

    Repo.insert!(%SpellslingersResult{game_result_id: spells.id, map: "flamingo"})

    Repo.insert!(%GameResultPlayer{
      game_result_id: spells.id,
      user_id: sam.id,
      name: "Sam",
      placement: 2,
      score: 95
    })

    {:ok, spells_view, _} = live(conn, ~p"/saved-lobby/#{lobby.name}/history/#{spells.id}")
    assert has_element?(spells_view, "#spellslingers-headline", "Everyone fell!")
    assert has_element?(spells_view, "#game-final-scores", "Flamingo Isle")
    assert has_element?(spells_view, "#game-final-scores", "95 dmg")
    refute has_element?(spells_view, "#game-drawings")
  end
end
