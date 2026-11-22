defmodule FlamingoWeb.GameResultLive do
  use FlamingoWeb, :live_view

  import FlamingoWeb.GameHistoryComponents

  alias Flamingo.{DrawingShare, GameHistory, SavedLobbies}
  alias FlamingoWeb.GameModes

  def mount(%{"saved_lobby_name" => name, "id" => game_id}, _session, socket) do
    with %{} = saved_lobby <- SavedLobbies.get_saved_lobby_by_name(name) || :missing_lobby,
         %{} = game <-
           GameHistory.get_game(saved_lobby.id, game_id) || {:missing_game, saved_lobby} do
      {:ok, assign_game(socket, saved_lobby, game)}
    else
      :missing_lobby ->
        {:ok,
         socket
         |> put_flash(:error, "That saved lobby doesn't exist.")
         |> push_navigate(to: ~p"/")}

      {:missing_game, saved_lobby} ->
        {:ok,
         socket
         |> put_flash(:error, "That game doesn't exist in this lobby.")
         |> push_navigate(to: ~p"/saved-lobby/#{saved_lobby.name}/history")}
    end
  end

  defp assign_game(socket, saved_lobby, game) do
    players_by_id = Map.new(game.players, &{&1.id, &1})

    drawings =
      Enum.map(game.drawings, fn drawing ->
        drawer = players_by_id[drawing.drawer_id]

        ops =
          case DrawingShare.decode_ops(drawing.payload) do
            {:ok, decoded} -> decoded
            _ -> []
          end

        share_payload =
          if drawer && former_player?(drawer) do
            DrawingShare.encode(%{
              drawer_name: "Former player",
              word: drawing.word,
              round_number: drawing.round_number,
              constraint: drawing.constraint,
              ops: ops
            })
          else
            drawing.payload
          end

        %{
          id: drawing.id,
          drawer_id: drawing.drawer_id,
          drawer: drawer,
          round_number: drawing.round_number,
          word: drawing.word,
          constraint: drawing.constraint,
          thumbs_up: drawing.thumbs_up,
          thumbs_down: drawing.thumbs_down,
          ops: ops,
          share_url: url(~p"/drawing") <> "##{share_payload}"
        }
      end)

    votes_by_player =
      Enum.reduce(drawings, %{}, fn d, acc ->
        Map.update(
          acc,
          d.drawer_id,
          %{thumbs_up: d.thumbs_up, thumbs_down: d.thumbs_down},
          fn prev ->
            %{
              thumbs_up: prev.thumbs_up + d.thumbs_up,
              thumbs_down: prev.thumbs_down + d.thumbs_down
            }
          end
        )
      end)

    teams =
      if game.mode == :coop, do: build_teams(game.players, drawings, votes_by_player), else: []

    drawing_counts = Enum.frequencies_by(drawings, & &1.drawer_id)

    selected_key =
      case game.mode do
        :spellslingers ->
          nil

        :coop ->
          team = Enum.find(teams, &(&1.drawings_count > 0)) || List.first(teams)
          team && team.team

        _ ->
          player =
            Enum.find(game.players, &(Map.get(drawing_counts, &1.id, 0) > 0)) ||
              List.first(game.players)

          player && player.id
      end

    assign(socket,
      saved_lobby: saved_lobby,
      game: game,
      mode_mod: GameModes.get(game.mode),
      players_by_id: players_by_id,
      votes_by_player: votes_by_player,
      drawings: drawings,
      teams: teams,
      selected_key: selected_key,
      selected_drawing_index: 0
    )
  end

  defp build_teams(players, drawings, votes_by_player) do
    team_by_player = Map.new(players, &{&1.id, &1.team})
    counts = drawings |> Enum.map(&team_by_player[&1.drawer_id]) |> Enum.frequencies()

    players
    |> Enum.group_by(& &1.team)
    |> Enum.map(fn {team, members} ->
      votes =
        Enum.reduce(members, %{thumbs_up: 0, thumbs_down: 0}, fn m, acc ->
          v = Map.get(votes_by_player, m.id, %{thumbs_up: 0, thumbs_down: 0})
          %{thumbs_up: acc.thumbs_up + v.thumbs_up, thumbs_down: acc.thumbs_down + v.thumbs_down}
        end)

      %{
        team: team,
        placement:
          members |> Enum.map(& &1.placement) |> Enum.reject(&is_nil/1) |> Enum.min(fn -> nil end),
        score: members |> Enum.map(& &1.score) |> Enum.reject(&is_nil/1) |> List.first(),
        members: Enum.sort_by(members, &{is_nil(&1.placement), &1.name}),
        votes: votes,
        drawings_count: Map.get(counts, team, 0)
      }
    end)
    |> Enum.sort_by(&{is_nil(&1.placement), &1.placement, -(&1.score || 0), &1.team})
  end

  def handle_event("select_player", %{"id" => player_id}, socket) do
    if Map.has_key?(socket.assigns.players_by_id, player_id),
      do: {:noreply, assign(socket, selected_key: player_id, selected_drawing_index: 0)},
      else: {:noreply, socket}
  end

  def handle_event("select_team", %{"team" => team_param}, socket) when is_binary(team_param) do
    case Integer.parse(team_param) do
      {team, ""} ->
        if Enum.any?(socket.assigns.teams, &(&1.team == team)),
          do: {:noreply, assign(socket, selected_key: team, selected_drawing_index: 0)},
          else: {:noreply, socket}

      _ ->
        {:noreply, socket}
    end
  end

  def handle_event("select_team", _params, socket), do: {:noreply, socket}

  def handle_event("previous_drawing", _params, socket) do
    {:noreply,
     assign(socket, :selected_drawing_index, max(socket.assigns.selected_drawing_index - 1, 0))}
  end

  def handle_event("next_drawing", _params, socket) do
    max_index = max(length(selected_drawings(socket.assigns)) - 1, 0)

    {:noreply,
     assign(
       socket,
       :selected_drawing_index,
       min(socket.assigns.selected_drawing_index + 1, max_index)
     )}
  end

  defp selected_drawings(%{game: %{mode: :spellslingers}}), do: []

  defp selected_drawings(%{
         game: %{mode: :coop, players: players},
         drawings: drawings,
         selected_key: team
       }) do
    team_ids = players |> Enum.filter(&(&1.team == team)) |> MapSet.new(& &1.id)
    Enum.filter(drawings, &MapSet.member?(team_ids, &1.drawer_id))
  end

  defp selected_drawings(%{drawings: drawings, selected_key: player_id}) do
    Enum.filter(drawings, &(&1.drawer_id == player_id))
  end

  def render(assigns) do
    visible_drawings = selected_drawings(assigns)
    drawing = Enum.at(visible_drawings, assigns.selected_drawing_index)

    selection_label =
      cond do
        assigns.game.mode == :coop && assigns.selected_key ->
          "Team #{assigns.selected_key}"

        player = assigns.players_by_id[assigns.selected_key] ->
          player.name

        true ->
          nil
      end

    arena =
      if assigns.game.mode == :spellslingers,
        do: map_name(assigns.game.spellslingers_result && assigns.game.spellslingers_result.map)

    assigns =
      assign(assigns,
        arena: arena,
        visible_drawings: visible_drawings,
        drawing: drawing,
        selection_label: selection_label
      )

    ~H"""
    <Layouts.app
      flash={@flash}
      current_scope={@current_scope}
      background={["grid-background", @mode_mod.theme().lobby]}
    >
      <Layouts.account_menu current_scope={@current_scope} />

      <div class={[
        "mx-auto space-y-4 px-6 pt-24 pb-20",
        if(@game.mode == :spellslingers, do: "max-w-2xl", else: "max-w-6xl")
      ]}>
        <div class="flex flex-wrap items-baseline justify-between gap-2">
          <.breadcrumb id="game-breadcrumb">
            <:item navigate={~p"/saved-lobby/#{@saved_lobby.name}"}>{@saved_lobby.name}</:item>
            <:item navigate={~p"/saved-lobby/#{@saved_lobby.name}/history"}>Game history</:item>
            <:item>{@mode_mod.title()}</:item>
          </.breadcrumb>

          <time
            id="game-finished-at"
            datetime={DateTime.to_iso8601(@game.finished_at)}
            class="text-sm font-semibold text-gray-600"
          >
            {format_date(@game.finished_at, :full)}
          </time>
        </div>

        <%= if @game.mode == :spellslingers do %>
          <.spellslingers_results
            game={@game}
            arena={@arena}
            lobby_name={@saved_lobby.name}
          />
        <% else %>
          <.card class="grid w-full overflow-hidden bg-white p-0 lg:grid-cols-[minmax(0,1fr)_minmax(0,1.1fr)]">
            <div
              id="game-final-scores"
              class="flex min-h-0 min-w-0 flex-col border-b-2 border-border lg:border-r-2 lg:border-b-0"
            >
              <div class="flex min-h-0 flex-1 flex-col gap-2 overflow-y-auto pb-4">
                <div class="flex items-center justify-between gap-2 px-4 pt-4">
                  <h1 id="game-result-heading" class="text-3xl font-bold">Results</h1>
                  <.mode_badge mode={@game.mode} />
                </div>

                <.team_standings
                  :if={@game.mode == :coop}
                  teams={@teams}
                  selected_team={@selected_key}
                />
                <.player_standings
                  :if={@game.mode != :coop}
                  players={@game.players}
                  votes_by_player={@votes_by_player}
                  selected_player_id={@selected_key}
                />
              </div>

              <div class="mt-auto border-t-2 border-border">
                <.button
                  id="game-back-to-history"
                  navigate={~p"/saved-lobby/#{@saved_lobby.name}/history"}
                  variant="ghost"
                  class="flex w-full items-center justify-start gap-2 rounded-none border-0! px-3! py-2!"
                >
                  <.icon name={:arrow_left} class="h-5 w-5" /> Back to history
                </.button>
              </div>
            </div>

            <.drawing_showcase
              id="game-drawings"
              heading_id="game-drawings-heading"
              aria_label={
                if(@game.mode == :coop,
                  do: "Selected team's drawings",
                  else: "Selected player's drawings"
                )
              }
              selected_key={@selected_key}
              drawing={@drawing}
              drawing_index={@selected_drawing_index}
              drawing_count={length(@visible_drawings)}
              canvas_id={@drawing && "history-drawing-#{@drawing.id}"}
              copy_id={@drawing && "share-drawing-#{@drawing.id}"}
              share_url={@drawing && @drawing.share_url}
            >
              <:subtitle>
                <p
                  :if={@game.mode == :coop && @drawing && @drawing.drawer}
                  id="final-drawing-artist"
                  class="mt-1 flex items-center justify-center gap-1.5 text-sm font-semibold text-gray-600"
                >
                  <span>Drawn by</span>
                  <.player_identity player={@drawing.drawer} avatar_class="h-6 w-6 shrink-0" />
                </p>
                <p
                  :if={@game.mode != :coop && @selection_label}
                  class="mt-0.5 text-xs font-semibold text-gray-500"
                >
                  {@selection_label}
                  <span :if={length(@visible_drawings) > 1}>
                    · {@selected_drawing_index + 1} of {length(@visible_drawings)}
                  </span>
                </p>
              </:subtitle>
            </.drawing_showcase>
          </.card>
        <% end %>
      </div>

      <.clipboard_handler />
    </Layouts.app>
    """
  end

  attr :players, :list, required: true
  attr :votes_by_player, :map, required: true
  attr :selected_player_id, :string, default: nil

  defp player_standings(assigns) do
    {placed, departed} = Enum.split_with(assigns.players, &(not is_nil(&1.placement)))

    assigns =
      assign(assigns,
        podium_players: Enum.take(placed, 3),
        remaining_players: Enum.drop(placed, 3) ++ departed
      )

    ~H"""
    <div id="game-score-list" class="w-full">
      <.podium :if={@podium_players != []}>
        <li
          :for={{player, idx} <- Enum.with_index(@podium_players)}
          id={"game-player-row-#{player.id}"}
          value={player.placement}
          class={podium_slot_class(idx)}
        >
          <% selected? = player.id == @selected_player_id %>
          <% votes = Map.get(@votes_by_player, player.id, %{thumbs_up: 0, thumbs_down: 0}) %>
          <button
            type="button"
            class="podium-player relative flex h-full w-full cursor-pointer items-center justify-center focus-visible:outline-2 focus-visible:outline-offset-4 focus-visible:outline-pink-500"
            phx-click="select_player"
            phx-value-id={player.id}
            data-player-id={player.id}
            data-selected={to_string(selected?)}
            aria-pressed={to_string(selected?)}
            aria-label={"Rank #{player.placement}: #{player.name}, #{format_score(player.score)} points"}
          >
            <span class={podium_label_class(idx)}>
              <.flamingo_avatar
                :if={player.user_id}
                avatar={(player.user && player.user.avatar) || %{}}
                class="h-10 w-10 shrink-0"
                label={"#{player.name}'s avatar"}
              />
              <span class={[
                "flex w-40 min-w-0 items-center text-sm sm:w-46 sm:text-base",
                idx == 1 && "justify-end text-right"
              ]}>
                <span class="podium-player-details relative flex min-w-0 items-center gap-1.5">
                  <span
                    class={[
                      "min-w-0 truncate font-bold",
                      former_player?(player) && "italic text-gray-500"
                    ]}
                    title={player.name}
                  >
                    {player.name}
                  </span>
                  <.badge :if={guest?(player)} class="text-[0.65rem]">Guest</.badge>
                  <.drawing_votes votes={votes} />
                  <span class="shrink-0 font-semibold tabular-nums text-pink-500">
                    {format_score(player.score)}
                  </span>
                </span>
              </span>
            </span>
            <.podium_step rank={idx} label={player.placement} />
          </button>
        </li>
      </.podium>

      <ol :if={@remaining_players != []} id="final-remaining-players" start="4">
        <li
          :for={player <- @remaining_players}
          id={"game-player-row-#{player.id}"}
          class={[
            "flex min-w-0 items-center transition-colors",
            if(player.id == @selected_player_id, do: "bg-pink-100", else: "hover:bg-pink-50")
          ]}
        >
          <% votes = Map.get(@votes_by_player, player.id, %{thumbs_up: 0, thumbs_down: 0}) %>
          <button
            type="button"
            class="flex min-w-0 flex-1 cursor-pointer items-center gap-2 px-3 py-2 text-left"
            phx-click="select_player"
            phx-value-id={player.id}
            data-player-id={player.id}
            data-selected={to_string(player.id == @selected_player_id)}
            aria-pressed={to_string(player.id == @selected_player_id)}
          >
            <span class={[
              "w-6 shrink-0 text-center text-lg tabular-nums",
              is_nil(player.placement) && "text-gray-400"
            ]}>
              {player.placement || "–"}
            </span>
            <div class="flex min-w-0 flex-1 flex-wrap items-center gap-2">
              <.player_identity player={player} avatar_class="h-10 w-10 shrink-0" />
            </div>
            <.drawing_votes votes={votes} />
            <span class="shrink-0 font-semibold tabular-nums text-pink-500">
              {format_score(player.score)}
            </span>
          </button>
        </li>
      </ol>
    </div>
    """
  end

  attr :teams, :list, required: true
  attr :selected_team, :integer, default: nil

  defp team_standings(assigns) do
    podium_teams =
      assigns.teams
      |> Enum.reject(&is_nil(&1.placement))
      |> Enum.take(3)

    assigns = assign(assigns, :podium_teams, podium_teams)

    ~H"""
    <div id="game-score-list" class="w-full">
      <.podium :if={@podium_teams != []}>
        <li
          :for={{team, idx} <- Enum.with_index(@podium_teams)}
          id={"game-team-row-#{team.team}"}
          value={team.placement}
          class={podium_slot_class(idx)}
        >
          <% selected? = team.team == @selected_team %>
          <button
            type="button"
            class="podium-player relative flex h-full w-full cursor-pointer items-center justify-center focus-visible:outline-2 focus-visible:outline-offset-4 focus-visible:outline-pink-500"
            phx-click="select_team"
            phx-value-team={team.team}
            data-team-id={team.team}
            data-selected={to_string(selected?)}
            aria-pressed={to_string(selected?)}
            aria-label={"Rank #{team.placement}: Team #{team.team}, #{format_score(team.score)} points"}
          >
            <span class={podium_label_class(idx)}>
              <span
                :if={Enum.any?(team.members, & &1.user_id)}
                class="flex shrink-0 items-end gap-0.5"
              >
                <.flamingo_avatar
                  :for={m <- team.members}
                  :if={m.user_id}
                  avatar={(m.user && m.user.avatar) || %{}}
                  class="h-8 w-8"
                  label={"#{m.name}'s avatar"}
                />
              </span>
              <span class={[
                "flex w-40 min-w-0 items-center text-sm sm:w-46 sm:text-base",
                idx == 1 && "justify-end text-right"
              ]}>
                <span class="podium-player-details relative flex min-w-0 items-center gap-1.5">
                  <span class="min-w-0 truncate font-bold">Team {team.team}</span>
                  <.drawing_votes votes={team.votes} />
                  <span class="shrink-0 font-semibold tabular-nums text-pink-500">
                    {format_score(team.score)}
                  </span>
                </span>
              </span>
            </span>
            <.podium_step rank={idx} label={team.placement} />
          </button>
        </li>
      </.podium>

      <ul class="space-y-0.5 px-2">
        <li
          :for={team <- @teams}
          id={"game-team-roster-#{team.team}"}
          class={[
            "rounded-base transition-colors",
            if(team.team == @selected_team, do: "bg-pink-100", else: "hover:bg-pink-50")
          ]}
        >
          <% selected? = team.team == @selected_team %>
          <button
            type="button"
            class="flex w-full cursor-pointer flex-wrap items-center gap-x-2 gap-y-1 px-2.5 py-2 text-left text-sm"
            phx-click="select_team"
            phx-value-team={team.team}
            data-team-id={team.team}
            data-selected={to_string(selected?)}
            aria-pressed={to_string(selected?)}
          >
            <span class={[
              "w-5 shrink-0 text-center font-bold tabular-nums",
              is_nil(team.placement) && "text-gray-400"
            ]}>
              {team.placement || "–"}
            </span>
            <span class="font-black text-black">Team {team.team}</span>
            <span class="flex min-w-0 flex-1 flex-wrap items-center gap-x-2 gap-y-1">
              <span
                :for={member <- team.members}
                id={"game-player-row-#{member.id}"}
                class="inline-flex items-center gap-1"
              >
                <.player_identity player={member} avatar_class="size-6 shrink-0" />
              </span>
            </span>
            <.drawing_votes votes={team.votes} />
            <span class="shrink-0 font-semibold tabular-nums text-pink-500">
              {format_score(team.score)}
            </span>
          </button>
        </li>
      </ul>
    </div>
    """
  end

  attr :game, :map, required: true
  attr :arena, :string, default: nil
  attr :lobby_name, :string, required: true

  defp spellslingers_results(assigns) do
    winners = Enum.filter(assigns.game.players, &(&1.placement == 1))

    headline =
      case winners do
        [w] -> "#{w.name} won!"
        [_ | _] = many -> "#{Enum.map_join(many, " & ", & &1.name)} tied!"
        [] -> "Everyone fell!"
      end

    assigns = assign(assigns, headline: headline, has_winner?: winners != [])

    ~H"""
    <.card id="game-final-scores" class="overflow-hidden bg-white p-0">
      <div class="p-6">
        <div class="mb-5 flex flex-col items-center text-center">
          <div class={[
            "mb-3 flex size-14 items-center justify-center rounded-full border-2 border-border",
            if(@has_winner?, do: "bg-amber-300", else: "bg-gray-200")
          ]}>
            <.icon name={if @has_winner?, do: :trophy, else: :skull} class="size-7 text-black" />
          </div>
          <h1 id="spellslingers-headline" class="text-2xl font-black">{@headline}</h1>
          <p :if={@arena} class="mt-0.5 text-sm font-semibold text-gray-600">{@arena}</p>
        </div>

        <ol id="game-score-list" class="-mx-2 space-y-1">
          <li
            :for={player <- @game.players}
            id={"game-player-row-#{player.id}"}
            class={[
              "flex items-center gap-3 rounded-base px-3 py-2.5",
              player.placement == 1 && "bg-amber-100/90"
            ]}
          >
            <span class={[
              "w-5 shrink-0 text-center font-bold tabular-nums",
              if(is_nil(player.placement), do: "text-gray-400", else: "text-gray-700")
            ]}>
              {player.placement || "–"}
            </span>
            <div class="flex min-w-0 flex-1 flex-wrap items-center gap-2">
              <.player_identity
                player={player}
                avatar_class="size-9 shrink-0"
                crown={player.placement == 1}
              />
            </div>
            <span class="shrink-0 text-sm font-semibold tabular-nums text-pink-500">
              {format_score(player.score)} <span class="text-gray-500">dmg</span>
            </span>
          </li>
        </ol>
      </div>

      <div class="border-t-2 border-border">
        <.button
          id="game-back-to-history"
          navigate={~p"/saved-lobby/#{@lobby_name}/history"}
          variant="ghost"
          class="flex w-full items-center justify-start gap-2 rounded-none border-0! px-4! py-2.5!"
        >
          <.icon name={:arrow_left} class="h-5 w-5" /> Back to history
        </.button>
      </div>
    </.card>
    """
  end
end
