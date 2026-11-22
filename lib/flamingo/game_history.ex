defmodule Flamingo.GameHistory do
  @moduledoc """
  Finished games in saved lobbies. Every mode with winners shares
  `game_results` and `game_result_players` (placing, score, team), which is
  all standings read; each mode family keeps its own details, such as
  drawings, in its own tables. Rows are written once, when a game finishes.

  Each game mode decides what a win means by turning its final result into a
  history record (`history/1`); Telephone has no winners and keeps none.
  """

  import Ecto.Query

  require Logger

  alias Flamingo.{DrawingShare, Repo, SavedLobbies}
  alias Flamingo.GameHistory.{GameResult, GameResultPlayer, ScribbleDrawing}

  @doc """
  Ranks scores so tied entries share a placing: `%{a: 9, b: 9, c: 4}` places
  `a` and `b` first and `c` third.
  """
  def placements(scores) do
    Map.new(scores, fn {key, score} ->
      {key, 1 + Enum.count(scores, fn {_, other} -> other > score end)}
    end)
  end

  @doc "Numbers a game's drawings by turn, in the order they were drawn."
  def drawings(drawings) do
    drawings
    |> Enum.with_index(1)
    |> Enum.map(fn {drawing, turn} -> Map.put(drawing, :turn, turn) end)
  end

  @doc """
  Saves a finished game. `record` is a mode's history merged with the room's
  `saved_lobby` name, game `mode` id, `started_at`, `finished_at`, and `seats`
  (name and account of everyone who held a seat during the game, by seat id).

  A mode's history holds `players` (seat id, placement, score, team), its own
  `details` row such as a `ScribbleResult`, and any `drawings`.
  """
  def record(record) do
    result =
      Repo.transact(fn ->
        case SavedLobbies.get_saved_lobby_by_name(record.saved_lobby) do
          nil -> {:error, :saved_lobby_not_found}
          saved_lobby -> {:ok, insert_game(saved_lobby, record)}
        end
      end)

    with {:error, reason} <- result do
      Logger.warning("Game in #{record.saved_lobby} was not recorded: #{inspect(reason)}")
      result
    end
  end

  defp insert_game(saved_lobby, record) do
    game =
      Repo.insert!(%GameResult{
        saved_lobby_id: saved_lobby.id,
        mode: record.mode,
        started_at: DateTime.truncate(record.started_at, :second),
        finished_at: DateTime.truncate(record.finished_at, :second)
      })

    Repo.insert!(%{record.details | game_result_id: game.id})

    players =
      for player <- record.players, seat = record.seats[player.seat_id], into: %{} do
        row =
          Repo.insert!(%GameResultPlayer{
            game_result_id: game.id,
            user_id: seat.user_id,
            name: seat.name,
            placement: player.placement,
            score: player.score,
            team: player.team
          })

        {player.seat_id, row}
      end

    drawings =
      for drawing <- record.drawings, drawer = players[drawing.drawer_id] do
        %{
          id: drawing.id,
          game_result_id: game.id,
          drawer_id: drawer.id,
          turn: drawing.turn,
          round_number: drawing.round_number,
          word: drawing.word,
          constraint: drawing.constraint && to_string(drawing.constraint),
          payload: DrawingShare.encode(Map.put(drawing, :drawer_name, drawer.name)),
          thumbs_up: drawing.thumbs_up,
          thumbs_down: drawing.thumbs_down
        }
      end

    Repo.insert_all(ScribbleDrawing, drawings)
    game
  end

  @doc """
  Lifetime standings for a saved lobby: wins and games played for each
  signed-in player, most wins first. A game is one win for every player
  placed first, whatever the mode. Guests never appear. Each player is shown
  with the name they last played under here and their account's avatar.
  """
  def standings(saved_lobby_id) do
    lobby_players =
      from p in GameResultPlayer,
        join: g in assoc(p, :game_result),
        where: g.saved_lobby_id == ^saved_lobby_id and not is_nil(p.user_id)

    latest =
      from [p, g] in lobby_players,
        join: u in assoc(p, :user),
        distinct: p.user_id,
        order_by: [p.user_id, desc: g.finished_at],
        select: {p.user_id, %{name: p.name, avatar: u.avatar}}

    latest = latest |> Repo.all() |> Map.new()

    from([p, g] in lobby_players,
      group_by: p.user_id,
      select: %{
        user_id: p.user_id,
        wins: filter(count(p.id), p.placement == 1),
        played: count(p.id)
      }
    )
    |> Repo.all()
    |> Enum.map(&Map.merge(&1, latest[&1.user_id]))
    |> Enum.sort_by(&{-&1.wins, &1.played, &1.name})
  end

  @doc "Keeps a deleted account's games for the other players, uncredited."
  def forget_user(user_id) do
    from(p in GameResultPlayer, where: p.user_id == ^user_id)
    |> Repo.update_all(set: [name: "Former player", user_id: nil])
  end
end
