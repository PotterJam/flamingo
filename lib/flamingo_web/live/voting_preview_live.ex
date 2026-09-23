defmodule FlamingoWeb.VotingPreviewLive do
  # Local review fixture; remove before shipping.
  use FlamingoWeb, :live_view

  alias Flamingo.GameModes.Scribble
  alias FlamingoWeb.ScribbleLive

  def mount(_params, session, socket) do
    {:ok, socket} = ScribbleLive.mount(%{"room_id" => "voting-preview"}, session, socket)

    players =
      Map.new([{"artist", "Alice"}, {"you", "You"}, {"other", "Bob"}], fn {id, name} ->
        {id, %{id: id, name: name, avatar: Flamingo.Avatar.default(), connected: true}}
      end)

    roster = %{players: players, player_order: ["artist", "you", "other"], host_id: "artist"}

    game = %{
      Scribble.new()
      | phase: :playing,
        drawer_id: "artist",
        word: "house",
        participants: Map.new(players, fn {id, _} -> {id, :active} end),
        scores: Map.new(players, fn {id, _} -> {id, 0} end)
    }

    socket =
      socket
      |> assign(preview_game: game, preview_roster: roster)
      |> project()
      |> push_event("drawing_state", %{
        events:
          Enum.map(
            [
              {200, 230, 350, 100},
              {350, 100, 500, 230},
              {500, 230, 200, 230},
              {230, 230, 230, 420},
              {230, 420, 470, 420},
              {470, 420, 470, 230},
              {310, 420, 310, 310},
              {310, 310, 380, 310},
              {380, 310, 380, 420}
            ],
            fn {x, y, end_x, end_y} ->
              %{
                "event_type" => "draw",
                "start_x" => x,
                "start_y" => y,
                "end_x" => end_x,
                "end_y" => end_y,
                "color" => "#000000",
                "line_width" => 5
              }
            end
          )
      })

    {:ok, socket}
  end

  def render(assigns), do: ScribbleLive.render(assigns)

  def handle_event("vote_drawing", %{"vote" => vote}, socket) when vote in ["up", "down"] do
    command(socket, {:vote_drawing, if(vote == "up", do: :up, else: :down)})
  end

  def handle_event("guess", %{"guess_form" => %{"guess" => text}}, socket) do
    command(socket, {:guess, text})
  end

  defp command(socket, command) do
    context = %{roster: socket.assigns.preview_roster, now: DateTime.utc_now()}

    {:ok, %{state: game}} =
      Scribble.command(socket.assigns.preview_game, "you", command, context)

    {:noreply, socket |> assign(:preview_game, game) |> project()}
  end

  defp project(socket) do
    snapshot = Scribble.view(socket.assigns.preview_game, "you", socket.assigns.preview_roster)

    socket
    |> assign(Map.drop(snapshot, [:feed]))
    |> assign(player_id: "you", show_word: snapshot.word_visible?)
    |> stream(:feed, snapshot.feed, reset: true)
  end
end
