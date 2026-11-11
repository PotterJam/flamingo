defmodule FlamingoWeb.ScribbleLive do
  use FlamingoWeb, :live_view

  alias Flamingo.{DrawingShare, Rooms, Words}
  alias FlamingoWeb.RoomRoute

  @palette ~w(
    #000000 #FFFFFF #C1C1C1 #505050 #EF120B #740A08
    #FF7700 #C23900 #FFE404 #E8A202 #08C202 #00461A
    #00FF91 #04785E #00B2FF #02569E #2220D3 #0E0865
    #A302BA #550069 #DF69A7 #883454 #FFAC8A #CC7C4D
    #A0522D #63300D
  )

  def mount(%{"room_id" => room_id} = _params, _session, socket) do
    {:ok,
     socket
     |> assign(
       room_id: room_id,
       resume_token: nil,
       player_id: nil,
       participation: :active,
       phase: nil,
       players: %{},
       player_order: [],
       final_players: %{},
       final_player_order: [],
       final_drawings: [],
       selected_player_id: nil,
       selected_drawing_index: 0,
       host_id: nil,
       drawer_id: nil,
       constraint: nil,
       spin_holder: nil,
       spin_available?: false,
       spin_started_at: nil,
       round_count: 3,
       game_variant: :classic,
       teams: %{},
       team_scores: %{},
       team_gains: %{},
       team_drawers: [],
       word_picker_id: nil,
       team_finished?: false,
       can_guess?: false,
       word_choices: nil,
       word_list_label: nil,
       turn_end_time: nil,
       word: nil,
       show_word: false,
       current_round: 0,
       correct_guesses: MapSet.new(),
       drawing_vote: nil,
       revealed_indices: [],
       feed_ids: MapSet.new(),
       guess_form: to_form(%{"guess" => ""}, as: :guess_form),
       score_gains: %{}
     )
     |> stream_configure(:feed, dom_id: &"feed-#{&1.id}")
     |> stream(:feed, [])}
  end

  def handle_params(%{"resume_token" => resume_token}, _uri, socket) do
    room_id = socket.assigns.room_id

    if connected?(socket) do
      case Rooms.connect(room_id, resume_token) do
        {:ok, snapshot} ->
          socket =
            socket
            |> assign(:resume_token, resume_token)
            |> route_snapshot(snapshot)

          {:noreply, push_event(socket, "play_sound", %{sound: "join"})}

        {:error, _reason} ->
          {:noreply, push_navigate(socket, to: ~p"/")}
      end
    else
      {:noreply, assign(socket, :resume_token, resume_token)}
    end
  end

  def handle_params(_params, _uri, socket) do
    {:noreply, push_navigate(socket, to: ~p"/")}
  end

  defp palette, do: @palette

  attr :player, :map, required: true
  attr :id, :string, required: true

  defp final_votes(assigns) do
    ~H"""
    <span
      :if={@player.thumbs_up > 0 or @player.thumbs_down > 0}
      id={"final-votes-#{@id}"}
      class="flex shrink-0 items-center gap-2 text-xs font-semibold sm:text-sm"
    >
      <span
        :if={@player.thumbs_up > 0}
        class="flex items-center gap-1 text-green-700"
        aria-label={"#{@player.thumbs_up} thumbs up"}
      >
        <.icon name={:thumbs_up} class="h-4 w-4" /> {@player.thumbs_up}
      </span>
      <span
        :if={@player.thumbs_down > 0}
        class="flex items-center gap-1 text-red-600"
        aria-label={"#{@player.thumbs_down} thumbs down"}
      >
        <.icon name={:thumbs_down} class="h-4 w-4" /> {@player.thumbs_down}
      </span>
    </span>
    """
  end

  attr :player_id, :string, required: true
  attr :host_id, :string, required: true
  attr :final_players, :map, required: true
  attr :final_drawings, :list, required: true
  attr :selected_player_id, :string, default: nil
  attr :selected_drawing_index, :integer, required: true
  attr :teams, :map, default: %{}
  slot :inner_block, required: true

  defp final_results(assigns) do
    selected_drawings =
      drawings_for_player(assigns.final_drawings, assigns.teams, assigns.selected_player_id)

    assigns =
      assign(assigns,
        selected_drawings: selected_drawings,
        drawing: Enum.at(selected_drawings, assigns.selected_drawing_index)
      )

    ~H"""
    <div class="flex min-h-dvh w-full items-center justify-center p-4 sm:p-8">
      <.card class="grid w-full max-w-6xl overflow-hidden bg-white p-0 lg:grid-cols-[minmax(0,1fr)_minmax(0,1.1fr)]">
        <div
          id="final-leaderboard"
          class="flex min-h-0 min-w-0 flex-col border-b-2 border-border lg:border-r-2 lg:border-b-0"
        >
          <div class="flex min-h-0 flex-1 flex-col gap-4 overflow-y-auto pb-4">
            <h2 class="px-4 pt-4 text-3xl font-bold">Results</h2>
            {render_slot(@inner_block)}
          </div>
          <div class="mt-auto border-t-2 border-border">
            <.button
              :if={@player_id == @host_id}
              id="return-to-lobby"
              phx-click="return_to_lobby"
              variant="ghost"
              class="flex w-full items-center justify-start gap-2 rounded-none border-0! px-3! py-2!"
            >
              <.icon name={:arrow_left} class="h-5 w-5" /> Back to lobby
            </.button>
            <p :if={@player_id != @host_id} class="px-3 py-2 text-sm text-gray-600">
              Waiting for the host to return to the lobby.
            </p>
          </div>
        </div>

        <div
          id="final-drawings"
          aria-label={
            if(@teams == %{}, do: "Selected player's drawings", else: "Selected team's drawings")
          }
          class="flex min-w-0 flex-col justify-center p-4 sm:p-6"
          phx-hook="FinalDrawingShowcase"
          data-selected-player-id={@selected_player_id}
        >
          <%= if is_nil(@drawing) do %>
            <div class="bg-white p-6 text-center font-bold">
              No drawings to show
            </div>
          <% else %>
            <% share_url = drawing_share_url(@drawing, @final_players) %>
            <% drawing_constraint = constraint_mode(Map.get(@drawing, :constraint)) %>
            <div class="w-full">
              <div class="mb-4 grid grid-cols-[3rem_minmax(0,1fr)_3rem] items-center">
                <div class="col-start-2 text-center">
                  <h3 id="final-drawing-word" class="text-2xl font-bold">
                    {@drawing.word}
                  </h3>
                  <% artist = @final_players[@drawing.drawer_id] %>
                  <p
                    :if={@teams != %{}}
                    id="final-drawing-artist"
                    class="mt-1 flex items-center justify-center gap-2 text-sm font-semibold text-gray-600"
                  >
                    <.flamingo_avatar
                      avatar={Map.get(artist, :avatar, %{})}
                      class="h-7 w-7 shrink-0"
                      label={"#{artist.name}'s avatar"}
                    />
                    <span class="min-w-0 truncate">
                      Drawn by <span class="font-bold text-black">{artist.name}</span>
                    </span>
                  </p>
                </div>
                <.button
                  id="replay-final-drawing"
                  type="button"
                  variant="ghost"
                  size="icon"
                  class="text-black"
                  data-replay-final-drawings
                  aria-label="Replay drawing"
                >
                  <.icon name={:refresh_cw} class="h-5 w-5" />
                </.button>
              </div>
              <div
                id={"final-drawing-#{@drawing.drawer_id}-round-#{@drawing.round_number}"}
                phx-hook="DrawingCanvas"
                phx-update="ignore"
                data-is-drawer="false"
                data-final-drawing-replay="true"
                data-final-drawing-events={Jason.encode!(@drawing.ops)}
                data-constraint={Map.get(@drawing, :constraint)}
              >
                <canvas width="700" height="500" class="aspect-[7/5] w-full bg-white"></canvas>
              </div>
              <p
                :if={drawing_constraint}
                id={"final-drawing-constraint-#{@drawing.drawer_id}-round-#{@drawing.round_number}"}
                class="mt-2 text-center text-sm font-bold text-yellow-600"
              >
                drawn with {drawing_constraint}
              </p>
              <nav
                aria-label="Drawing navigation"
                class="mt-4 flex items-center justify-center gap-2"
              >
                <.button
                  id="previous-final-drawing"
                  variant="ghost"
                  phx-click="previous_drawing"
                  disabled={@selected_drawing_index == 0}
                  class="flex items-center gap-1"
                  aria-label="Previous drawing"
                >
                  <.icon name={:arrow_left} class="h-4 w-4" /> Prev
                </.button>
                <.button
                  variant="ghost"
                  on_confirm_click={JS.dispatch("phx:copy", detail: %{text: share_url})}
                  id={"copy-final-drawing-#{@drawing.drawer_id}-round-#{@drawing.round_number}"}
                  data-drawing-share-url={share_url}
                >
                  <span class="flex items-center gap-1">
                    <.icon name={:copy} class="h-4 w-4" /> Copy
                  </span>
                </.button>
                <.button
                  id="next-final-drawing"
                  variant="ghost"
                  phx-click="next_drawing"
                  disabled={@selected_drawing_index >= length(@selected_drawings) - 1}
                  class="flex items-center gap-1"
                  aria-label="Next drawing"
                >
                  Next <.icon name={:arrow_right} class="h-4 w-4" />
                </.button>
              </nav>
            </div>
          <% end %>
        </div>
      </.card>
    </div>
    """
  end

  attr :final_players, :map, required: true
  attr :final_player_order, :list, required: true
  attr :selected_player_id, :string, default: nil

  defp player_standings(assigns) do
    assigns =
      assign(
        assigns,
        :ranked_players,
        Enum.sort_by(assigns.final_player_order, &(-Map.fetch!(assigns.final_players, &1).score))
      )

    ~H"""
    <div id="final-score-rows" class="w-full">
      <.podium>
        <%= for {pid, idx} <- @ranked_players |> Enum.take(3) |> Enum.with_index() do %>
          <% player = Map.fetch!(@final_players, pid) %>
          <li id={"final-score-row-#{pid}"} value={idx + 1} class={podium_slot_class(idx)}>
            <button
              type="button"
              class="podium-player relative flex h-full w-full cursor-pointer items-center justify-center focus-visible:outline-2 focus-visible:outline-offset-4 focus-visible:outline-pink-500"
              phx-click="select_player"
              phx-value-player-id={pid}
              data-player-id={pid}
              data-selected={to_string(pid == @selected_player_id)}
              aria-pressed={to_string(pid == @selected_player_id)}
              aria-label={"Rank #{idx + 1}: #{player.name}, #{player.score} points"}
            >
              <span class={podium_label_class(idx)}>
                <.flamingo_avatar
                  avatar={Map.get(player, :avatar, %{})}
                  class="h-10 w-10 shrink-0"
                  label={"#{player.name}'s avatar"}
                />
                <.podium_details
                  rank={idx}
                  name={player.name}
                  votes={player}
                  score={player.score}
                  id={pid}
                />
              </span>
              <.podium_step rank={idx} />
            </button>
          </li>
        <% end %>
      </.podium>
      <ol id="final-remaining-players" start="4">
        <%= for {pid, idx} <- @ranked_players |> Enum.drop(3) |> Enum.with_index(3) do %>
          <li
            id={"final-score-row-#{pid}"}
            class={[
              "flex min-w-0 items-center transition-colors",
              pid == @selected_player_id && "bg-pink-100",
              pid != @selected_player_id && "hover:bg-pink-50"
            ]}
          >
            <button
              type="button"
              class="flex min-w-0 flex-1 items-center gap-2 px-3 py-2 text-left"
              phx-click="select_player"
              phx-value-player-id={pid}
              data-player-id={pid}
              data-selected={to_string(pid == @selected_player_id)}
              aria-pressed={to_string(pid == @selected_player_id)}
            >
              <span class="text-lg">
                {idx + 1}
              </span>
              <.flamingo_avatar
                avatar={Map.get(Map.get(@final_players, pid), :avatar, %{})}
                class="h-10 w-10 shrink-0"
                label={"#{Map.get(@final_players, pid).name}'s avatar"}
              />
              <span class="min-w-0 flex-1 truncate font-bold">
                {Map.get(@final_players, pid).name}
              </span>
              <.final_votes player={Map.fetch!(@final_players, pid)} id={pid} />
              <span class="shrink-0 text-pink-500 font-semibold">
                {Map.get(@final_players, pid).score}
              </span>
            </button>
          </li>
        <% end %>
      </ol>
    </div>
    """
  end

  attr :teams, :map, required: true
  attr :team_scores, :map, required: true
  attr :final_players, :map, required: true
  attr :final_player_order, :list, required: true
  attr :selected_player_id, :string, default: nil

  defp team_standings(assigns) do
    ranked_teams =
      assigns.teams
      |> Map.values()
      |> Enum.uniq()
      |> Enum.sort_by(&{-Map.get(assigns.team_scores, &1, 0), &1})
      |> Enum.map(fn team ->
        members = Enum.filter(assigns.final_player_order, &(assigns.teams[&1] == team))

        votes = %{
          thumbs_up: Enum.sum(Enum.map(members, &assigns.final_players[&1].thumbs_up)),
          thumbs_down: Enum.sum(Enum.map(members, &assigns.final_players[&1].thumbs_down))
        }

        %{
          id: team,
          members: members,
          score: Map.get(assigns.team_scores, team, 0),
          votes: votes,
          selected?: assigns.selected_player_id in members
        }
      end)

    assigns = assign(assigns, :ranked_teams, ranked_teams)

    ~H"""
    <div id="final-team-rows" class="w-full">
      <.podium>
        <li
          :for={{team, idx} <- @ranked_teams |> Enum.take(3) |> Enum.with_index()}
          id={"final-team-row-#{team.id}"}
          value={idx + 1}
          class={podium_slot_class(idx)}
        >
          <button
            type="button"
            class="podium-player relative flex h-full w-full cursor-pointer items-center justify-center focus-visible:outline-2 focus-visible:outline-offset-4 focus-visible:outline-pink-500"
            phx-click="select_player"
            phx-value-player-id={hd(team.members)}
            data-team-id={team.id}
            data-selected={to_string(team.selected?)}
            aria-pressed={to_string(team.selected?)}
            aria-label={"Rank #{idx + 1}: Team #{team.id}, #{team.score} points"}
          >
            <span class={podium_label_class(idx)}>
              <.team_avatars team={team} final_players={@final_players} />
              <.podium_details
                rank={idx}
                name={"Team #{team.id}"}
                votes={team.votes}
                score={team.score}
                id={"team-#{team.id}"}
              />
            </span>
            <.podium_step rank={idx} />
          </button>
        </li>
      </.podium>
      <ol id="final-remaining-teams" start="4">
        <li
          :for={{team, idx} <- @ranked_teams |> Enum.drop(3) |> Enum.with_index(3)}
          id={"final-team-row-#{team.id}"}
          class={[
            "flex min-w-0 items-center transition-colors",
            team.selected? && "bg-pink-100",
            !team.selected? && "hover:bg-pink-50"
          ]}
        >
          <button
            type="button"
            class="flex min-w-0 flex-1 cursor-pointer items-center gap-2 px-3 py-2 text-left"
            phx-click="select_player"
            phx-value-player-id={hd(team.members)}
            data-team-id={team.id}
            data-selected={to_string(team.selected?)}
            aria-pressed={to_string(team.selected?)}
          >
            <span class="text-lg">{idx + 1}</span>
            <.team_avatars team={team} final_players={@final_players} />
            <span class="min-w-0 flex-1 truncate font-bold">Team {team.id}</span>
            <.final_votes player={team.votes} id={"team-#{team.id}"} />
            <span class="shrink-0 font-semibold text-pink-500">{team.score}</span>
          </button>
        </li>
      </ol>
    </div>
    """
  end

  attr :team, :map, required: true
  attr :final_players, :map, required: true

  defp team_avatars(assigns) do
    ~H"""
    <span class="flex shrink-0 items-end gap-0.5">
      <.flamingo_avatar
        :for={id <- @team.members}
        avatar={Map.get(@final_players[id], :avatar, %{})}
        class="h-8 w-8"
        label={@final_players[id].name}
      />
    </span>
    """
  end

  slot :inner_block, required: true

  defp podium(assigns) do
    ~H"""
    <div class="overflow-x-auto">
      <div class="min-w-[29rem] sm:min-w-[33rem]">
        <ol
          id="final-podium"
          aria-label="Podium"
          class="mx-auto grid w-fit grid-cols-[repeat(3,2.5rem)] items-end pt-16 pb-6 sm:grid-cols-[repeat(3,3rem)]"
        >
          {render_slot(@inner_block)}
        </ol>
      </div>
    </div>
    """
  end

  attr :rank, :integer, required: true
  attr :name, :string, required: true
  attr :votes, :map, required: true
  attr :score, :integer, required: true
  attr :id, :string, required: true

  defp podium_details(assigns) do
    ~H"""
    <span class={[
      "flex w-40 min-w-0 items-center text-sm sm:w-46 sm:text-base",
      @rank == 1 && "justify-end text-right"
    ]}>
      <span class="podium-player-details relative flex min-w-0 items-center gap-1 sm:gap-2">
        <span class="min-w-0 truncate font-bold" title={@name}>{@name}</span>
        <.final_votes player={@votes} id={@id} />
        <span class="shrink-0 font-semibold text-pink-500">{@score}</span>
      </span>
    </span>
    """
  end

  attr :rank, :integer, required: true

  defp podium_step(assigns) do
    ~H"""
    <span
      aria-hidden="true"
      class={[
        "relative z-10 flex h-full w-full items-center justify-center overflow-hidden border-2 border-border text-xl font-black",
        @rank == 0 && "bg-yellow-300 text-yellow-400",
        @rank == 1 && "border-r-0 bg-slate-200 text-slate-300",
        @rank == 2 && "border-l-0 bg-orange-300 text-[#d9a36b]"
      ]}
    >
      <span
        :for={stripe <- 0..11}
        class="podium-stripe pointer-events-none"
        style={"--stripe-index: #{stripe}; --stripe-delay: #{rem(stripe, 3) * 60}ms"}
      >
      </span>
      <span class="relative text-black">{@rank + 1}</span>
    </span>
    """
  end

  defp podium_slot_class(rank),
    do: [
      "relative row-start-1",
      rank == 0 && "col-start-2 h-26",
      rank == 1 && "col-start-1 h-16",
      rank == 2 && "col-start-3 h-6"
    ]

  defp podium_label_class(rank),
    do: [
      "absolute bottom-full -mb-2 flex items-center gap-2 px-3 py-2",
      rank == 1 && "right-1/2 -mr-8 flex-row-reverse",
      rank != 1 && "left-1/2 -ml-8"
    ]

  defp constraint_label(:hidden_canvas), do: "Draw blind — your canvas is hidden"
  defp constraint_label(:single_stroke), do: "One stroke — don't lift your pen"
  defp constraint_label(:straight_lines), do: "Straight lines only"
  defp constraint_label(:rotating_canvas), do: "Moving target — the canvas is rotating"
  defp constraint_label(:mirror), do: "Mirror mode — horizontal movement is reversed"
  defp constraint_label(:big_brush), do: "Heavy hands make big brush strokes"
  defp constraint_label(:rainbow_strokes), do: "All the colours of the rainbow"
  defp constraint_label(:fading_ink), do: "Draw fast! Your ink will fade"
  defp constraint_label(:kaleidoscope), do: "Kaleidoscope — every stroke is reflected eight ways"
  defp constraint_label(_constraint), do: nil

  defp constraint_mode(:hidden_canvas), do: "draw blind"
  defp constraint_mode(:single_stroke), do: "one stroke"
  defp constraint_mode(:straight_lines), do: "straight lines only"
  defp constraint_mode(:rotating_canvas), do: "moving target"
  defp constraint_mode(:mirror), do: "mirror mode"
  defp constraint_mode(:big_brush), do: "big brush"
  defp constraint_mode(:rainbow_strokes), do: "rainbow strokes"
  defp constraint_mode(:fading_ink), do: "fading ink"
  defp constraint_mode(:kaleidoscope), do: "kaleidoscope"
  defp constraint_mode(_constraint), do: nil

  defp mode_label(:coop), do: "TEAMS"
  defp mode_label(:constraint_roulette), do: "ROULETTE"
  defp mode_label(_variant), do: "SCRIBBLE"

  defp winning_player_id(players, player_order) do
    Enum.max_by(player_order, fn pid -> Map.get(players, pid).score end, fn -> nil end)
  end

  defp selected_or_winning_player_id(players, player_order, selected_player_id) do
    if selected_player_id && Map.has_key?(players, selected_player_id) do
      selected_player_id
    else
      winning_player_id(players, player_order)
    end
  end

  # In Teams mode a selection covers every drawing by the selected player's team.
  defp drawings_for_player(final_drawings, teams, player_id) do
    team = Map.get(teams, player_id)

    final_drawings
    |> Enum.filter(&(&1.drawer_id == player_id or (team && teams[&1.drawer_id] == team)))
    |> Enum.sort_by(& &1.round_number)
  end

  defp drawing_share_url(drawing, players) do
    player = Map.fetch!(players, drawing.drawer_id)

    encoded =
      drawing
      |> Map.put(:drawer_name, player.name)
      |> DrawingShare.encode()

    url(~p"/drawing") <> "##{encoded}"
  end

  defp sync_round_audio(socket) do
    push_event(socket, "sync_round_audio", %{
      phase: Atom.to_string(socket.assigns.phase),
      end_time:
        if(socket.assigns.turn_end_time,
          do: DateTime.to_iso8601(socket.assigns.turn_end_time),
          else: nil
        )
    })
  end

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} background="">
      <%= if @phase in [:word_choice, :playing, :turn_reveal] do %>
        <.flamingo_background
          game_mode={@game_variant}
          label={mode_label(@game_variant)}
        />
        <div class="flex min-h-screen w-full items-center justify-center p-6">
          <div class="flex h-[675px] w-full max-w-[1200px] flex-col gap-10">
            <div
              :if={@participation == :spectator}
              id="spectator-notice"
              class="mx-auto -mb-3 flex items-center gap-2 rounded-full border-2 border-pink-300 bg-white px-4 py-2 text-sm font-bold text-pink-700 shadow-sm"
            >
              <.icon name={:eye} class="h-4 w-4" />
              <%= cond do %>
                <% @game_variant != :coop -> %>
                  Spectating this turn
                <% @teams[@player_id] -> %>
                  Your team sits out this round
                <% true -> %>
                  Spectating until the next game
              <% end %>
            </div>
            <.game_header
              word={@word}
              show_word={@show_word or MapSet.member?(@correct_guesses, @player_id)}
              revealed_indices={@revealed_indices}
              turn_end_time={@turn_end_time}
              show_timer={@phase == :playing}
            />

            <div class="flex min-h-0 w-full flex-1 flex-row gap-3 pb-1 pr-1">
              <.player_list_panel
                players={@players}
                player_order={@player_order}
                teams={@teams}
                team_scores={@team_scores}
                team_drawers={@team_drawers}
                viewer_id={@player_id}
                drawer_id={@drawer_id}
                correct_guesses={@correct_guesses}
                current_round={@current_round + 1}
                round_count={@round_count}
              />

              <%!-- A stable wrapper lets LiveView swap the phase panel in place; without
                   it the chat box is moved in the DOM, which resets its scroll position --%>
              <div id="scribble-stage" class="flex w-[704px] shrink-0">
                <%= cond do %>
                  <% @phase == :word_choice -> %>
                    <.box class="flex w-full items-center justify-center bg-white">
                      <%= if @player_id == @drawer_id and @participation == :active and @word_choices != [] do %>
                        <div class="relative flex flex-col items-center gap-8">
                          <.starburst_timer
                            position_class="absolute -top-36 -right-16"
                            timer_id="word-choice-timer"
                            end_time={@turn_end_time && DateTime.to_iso8601(@turn_end_time)}
                          />
                          <h2 class="text-3xl font-black">Choose a word</h2>
                          <.word_choice_buttons
                            choices={@word_choices}
                            id="scribble-word-choices"
                            id_prefix="scribble-word-choice"
                            event="select_word"
                          />
                        </div>
                      <% else %>
                        <div class="relative flex flex-col items-center gap-3">
                          <.starburst_timer
                            position_class="absolute -bottom-32 -right-20"
                            size_class="h-28 w-28"
                            text_class="text-2xl"
                            timer_id="word-choice-timer"
                            end_time={@turn_end_time && DateTime.to_iso8601(@turn_end_time)}
                          />
                          <p id="word-picker" class="text-3xl font-black">
                            <span class="font-hero text-[2.5rem] leading-none text-pink-400">{Map.get(@players, @word_picker_id || @drawer_id).name}</span>{" "}is picking a word
                          </p>
                        </div>
                      <% end %>
                    </.box>
                  <% true -> %>
                    <div class="relative flex w-full flex-col gap-4">
                      <div
                        :if={@constraint}
                        id="constraint-banner"
                        class="absolute inset-x-8 -top-5 z-20 flex items-center justify-center"
                      >
                        <span class="border-2 border-border bg-yellow-200 px-4 py-1 font-hero text-lg font-black shadow-shadow">
                          {constraint_label(@constraint)}
                        </span>
                      </div>
                      <%= if @phase == :turn_reveal or @team_finished? do %>
                        <div
                          id="turn-reveal-overlay"
                          class={[
                            "absolute inset-x-0 top-0 z-10 m-[2px] flex h-[500px] items-center justify-center text-center",
                            if(
                              @constraint == :hidden_canvas and @player_id == @drawer_id and
                                @participation == :active,
                              do: "bg-white/20",
                              else: "bg-white/75 backdrop-blur-[2px]"
                            )
                          ]}
                        >
                          <div class="flex w-full flex-col items-center gap-4 px-6">
                            <div>
                              <p class="text-xl font-black">
                                {if @team_finished? and @phase == :playing,
                                  do: "Team finished — others are still guessing",
                                  else: "The word was"}
                              </p>
                              <p class="font-hero text-5xl leading-none font-black text-pink-400">
                                {@word}
                              </p>
                            </div>
                            <ul
                              id="turn-reveal-score-gains"
                              class="grid w-fit grid-flow-col grid-rows-5 auto-cols-[18rem] gap-x-4 gap-y-1"
                            >
                              <%= for {pid, gain} <- Enum.sort_by(@score_gains, fn {_pid, g} -> -g end) do %>
                                <li
                                  id={"score-gain-row-#{pid}"}
                                  class="flex min-w-0 items-center gap-2 px-3 py-1"
                                >
                                  <.flamingo_avatar
                                    avatar={Map.get(Map.get(@players, pid), :avatar, %{})}
                                    class="h-8 w-8 shrink-0"
                                    label={"#{Map.get(@players, pid).name}'s avatar"}
                                  />
                                  <span class="min-w-0 flex-1 truncate">
                                    {Map.get(@players, pid).name}
                                  </span>
                                  <span class={[
                                    "shrink-0",
                                    "font-semibold",
                                    if(gain > 0, do: "text-green-700"),
                                    if(gain < 0, do: "text-red-600"),
                                    if(gain == 0, do: "text-gray-700")
                                  ]}>
                                    {if(gain > 0, do: "+#{gain}", else: "#{gain}")}
                                  </span>
                                </li>
                              <% end %>
                            </ul>
                            <ul
                              :if={@game_variant == :coop}
                              id="coop-score-gains"
                              class="space-y-1 font-bold"
                            >
                              <li :for={{team, gain} <- Enum.sort(@team_gains)}>
                                Team {team} +{gain}
                              </li>
                            </ul>
                            <.starburst_timer
                              position_class=""
                              size_class="h-20 w-20"
                              text_class="text-xl"
                              timer_id="turn-reveal-timer"
                              end_time={@turn_end_time && DateTime.to_iso8601(@turn_end_time)}
                            />
                          </div>
                        </div>
                      <% end %>

                      <.drawing_canvas
                        id="drawing-canvas"
                        is_drawer={
                          @player_id == @drawer_id and @participation == :active and
                            not @team_finished?
                        }
                        constraint={@constraint}
                        spin_started_at={@spin_started_at}
                        phase={@phase}
                        show_toolbar={
                          @phase == :playing and @player_id == @drawer_id and
                            @participation == :active and not @team_finished?
                        }
                        palette={palette()}
                      />

                      <div
                        :if={@spin_holder == @player_id}
                        id="spin-charge"
                        class="flex items-center justify-between gap-3 rounded-base border-2 border-border bg-yellow-100 px-4 py-2"
                      >
                        <div>
                          <p class="text-sm font-bold">A little last-place mischief</p>
                          <p class="text-xs">One spin this round. Use before guessing correctly.</p>
                        </div>
                        <.button
                          id="use-spin"
                          phx-click="use_spin"
                          disabled={!@spin_available?}
                          size="sm"
                        >
                          <.icon name={:refresh_cw} class="size-4" /> Spin canvas
                        </.button>
                      </div>

                      <%= if @phase in [:playing, :turn_reveal] and (@can_guess? or (@game_variant == :coop and @participation == :active and @player_id != @drawer_id)) do %>
                        <div
                          id="guess-row"
                          class={[
                            "relative z-10 flex w-full items-center gap-2",
                            @phase == :turn_reveal && "justify-center"
                          ]}
                        >
                          <span :if={@phase == :turn_reveal} class="font-hero text-xl font-bold">
                            Cast your vote
                          </span>
                          <div id="drawing-votes" class="flex shrink-0">
                            <.button
                              :for={{vote, icon} <- [{:down, :thumbs_down}, {:up, :thumbs_up}]}
                              id={"vote-drawing-#{vote}"}
                              type="button"
                              variant="ghost"
                              size="sm"
                              class="drawing-vote flex h-10 w-10 items-center justify-center"
                              data-vote={vote}
                              phx-click={
                                JS.set_attribute({"aria-pressed", "false"},
                                  to: "#drawing-votes button"
                                )
                                |> JS.set_attribute({"aria-pressed", "true"})
                                |> JS.push("vote_drawing")
                                |> JS.transition("drawing-vote-pop",
                                  to: "#vote-drawing-#{vote} svg",
                                  time: 280,
                                  blocking: false
                                )
                              }
                              phx-value-vote={vote}
                              aria-label={"Thumbs #{vote}"}
                              aria-pressed={to_string(@drawing_vote == vote)}
                            >
                              <.icon name={icon} class="h-5 w-5" />
                            </.button>
                          </div>
                          <%= if @phase == :playing and not @team_finished? do %>
                            <%= if MapSet.member?(@correct_guesses, @player_id) do %>
                              <.box class="min-w-0 flex-1 bg-green-100 p-3 text-center font-bold text-green-800">
                                You guessed it!
                              </.box>
                            <% else %>
                              <.word_submission_form
                                form={@guess_form}
                                field={@guess_form[:guess]}
                                id="guess-form"
                                input_id="guess-input"
                                button_id="guess-button"
                                submit="guess"
                                placeholder="Type your guess..."
                                button_label="Guess"
                                class="min-w-0 flex-1"
                                hook="FlamingoWeb.ScribbleLive.GuessForm"
                                mounted={JS.focus()}
                              >
                                <:prefix>
                                  <span
                                    id="guess-letter-count"
                                    class="absolute left-0 top-full mt-1 font-hero text-sm leading-none font-medium text-black"
                                  >
                                  </span>
                                </:prefix>
                              </.word_submission_form>
                            <% end %>
                          <% end %>
                        </div>
                      <% end %>
                    </div>
                <% end %>
              </div>

              <.box class="relative z-10 flex min-h-0 w-full flex-1 flex-col bg-white p-0">
                <p
                  :if={@word_list_label}
                  id="word-list-label"
                  class="absolute -top-8 right-1 whitespace-nowrap text-xl leading-none font-black text-black"
                >
                  {@word_list_label}
                </p>
                <%!-- column-reverse anchors the scroll position to the bottom, so the
                     browser keeps the newest message in view without any JS --%>
                <div class="flex min-h-0 flex-1 flex-col-reverse overflow-y-auto">
                  <div id="game-feed" phx-update="stream" class="mb-auto flex flex-col">
                    <p
                      :for={{dom_id, entry} <- @streams.feed}
                      id={dom_id}
                      class={[
                        "p-1 text-xs",
                        entry.kind == :system && "font-semibold text-pink-600",
                        entry.kind == :correct && "font-semibold text-green-600",
                        entry.kind == :like && "font-semibold text-emerald-600",
                        entry.kind == :dislike && "font-semibold text-red-600",
                        entry.kind == :close && "font-semibold text-amber-600",
                        entry.kind == :guess && "text-foreground",
                        entry.kind == :info && "text-gray-500"
                      ]}
                    >
                      {entry.text}
                    </p>
                  </div>
                </div>
              </.box>
            </div>
          </div>
        </div>
      <% end %>
      <%= if @phase == :game_ended do %>
        <.flamingo_background
          game_mode={@game_variant}
          label={mode_label(@game_variant)}
        />
        <% selected_player_id =
          selected_or_winning_player_id(
            @final_players,
            @final_player_order,
            @selected_player_id
          ) %>
        <.final_results
          player_id={@player_id}
          host_id={@host_id}
          final_players={@final_players}
          final_drawings={@final_drawings}
          selected_player_id={selected_player_id}
          selected_drawing_index={@selected_drawing_index}
          teams={if(@game_variant == :coop, do: @teams, else: %{})}
        >
          <%= if @game_variant == :coop do %>
            <.team_standings
              teams={@teams}
              team_scores={@team_scores}
              final_players={@final_players}
              final_player_order={@final_player_order}
              selected_player_id={selected_player_id}
            />
          <% else %>
            <.player_standings
              final_players={@final_players}
              final_player_order={@final_player_order}
              selected_player_id={selected_player_id}
            />
          <% end %>
        </.final_results>
      <% end %>

      <.clipboard_handler />
      <script :type={Phoenix.LiveView.ColocatedHook} name=".GuessForm">
        export default {
          mounted() {
            const input = this.el.querySelector("#guess-input")
            const count = this.el.querySelector("#guess-letter-count")
            const formatCount = (text) => {
              if (!text.trim()) return ""

              return text
                .trim()
                .split(" ")
                .map((word) => Array.from(word).length)
                .join(" ")
            }
            const update = () => {
              count.textContent = formatCount(input.value)
            }

            update()
            input.focus()
            input.addEventListener("input", update)
            this.el.addEventListener("submit", () => {
              // Let LiveView serialize the submitted value before clearing the visible input.
              setTimeout(() => {
                this.el.reset()
                update()
                input.focus()
              }, 0)
            })
          }
        }
      </script>
    </Layouts.app>
    """
  end

  def handle_event("return_to_lobby", _params, socket) do
    case Rooms.return_to_lobby(socket.assigns.room_id) do
      :ok ->
        {:noreply, socket}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Cannot return to lobby: #{reason}")}
    end
  end

  def handle_event("select_word", %{"choice" => word}, socket) do
    Rooms.select_word(socket.assigns.room_id, word)
    {:noreply, socket}
  end

  def handle_event("draw_event", event, socket) do
    Rooms.draw_event(socket.assigns.room_id, event)
    {:noreply, socket}
  end

  def handle_event("use_spin", _params, socket) do
    case Rooms.command(socket.assigns.room_id, :use_spin) do
      :ok -> {:noreply, socket}
      {:error, _} -> {:noreply, put_flash(socket, :error, "Spin isn't available this turn.")}
    end
  end

  def handle_event("vote_drawing", %{"vote" => vote}, socket) when vote in ["up", "down"] do
    Rooms.command(socket.assigns.room_id, {:vote_drawing, if(vote == "up", do: :up, else: :down)})
    {:noreply, socket}
  end

  def handle_event("guess", %{"guess_form" => %{"guess" => text}}, socket) do
    socket =
      case Rooms.guess(socket.assigns.room_id, text) do
        :incorrect -> push_event(socket, "play_sound", %{sound: "wrongGuess"})
        _result -> socket
      end

    {:noreply, socket}
  end

  def handle_event("select_player", %{"player-id" => player_id}, socket) do
    {:noreply, assign(socket, selected_player_id: player_id, selected_drawing_index: 0)}
  end

  def handle_event("previous_drawing", _params, socket) do
    {:noreply, update(socket, :selected_drawing_index, &max(&1 - 1, 0))}
  end

  def handle_event("next_drawing", _params, socket) do
    assigns = socket.assigns

    player_id =
      selected_or_winning_player_id(
        assigns.final_players,
        assigns.final_player_order,
        assigns.selected_player_id
      )

    drawings = drawings_for_player(assigns.final_drawings, assigns.teams, player_id)
    last_index = max(length(drawings) - 1, 0)
    {:noreply, update(socket, :selected_drawing_index, &min(&1 + 1, last_index))}
  end

  def handle_info({:room_snapshot, snapshot}, socket) do
    {:noreply, route_snapshot(socket, snapshot)}
  end

  def handle_info({:draw_event, event}, socket) do
    {:noreply, push_event(socket, "draw_event", event)}
  end

  defp route_snapshot(socket, snapshot) do
    if RoomRoute.screen(snapshot) == :scribble do
      apply_snapshot(socket, snapshot)
    else
      RoomRoute.navigate(socket, snapshot)
    end
  end

  defp apply_snapshot(socket, snapshot) do
    initial? = is_nil(socket.assigns.player_id)
    old_phase = socket.assigns.phase
    old_turn_end_time = socket.assigns.turn_end_time
    old_count = map_size(socket.assigns.players)
    old_feed_ids = socket.assigns.feed_ids
    # The feed only grows during a game, so append new entries instead of
    # resetting the stream, which would empty the container and lose its scroll.
    new_feed = Enum.reject(snapshot.feed, &MapSet.member?(old_feed_ids, &1.id))
    newly_correct = MapSet.difference(snapshot.correct_guesses, socket.assigns.correct_guesses)
    game_ended? = snapshot.phase == :game_ended

    final_players = if game_ended?, do: snapshot.final_players, else: %{}
    final_player_order = if game_ended?, do: snapshot.final_player_order, else: []
    final_drawings = if game_ended?, do: snapshot.final_drawings, else: []

    socket =
      socket
      |> assign(
        player_id: snapshot.viewer_id,
        participation: snapshot.participation,
        phase: snapshot.phase,
        players: snapshot.players,
        player_order: snapshot.player_order,
        host_id: snapshot.host_id,
        drawer_id: snapshot.drawer_id,
        final_players: final_players,
        final_player_order: final_player_order,
        final_drawings: final_drawings,
        selected_player_id:
          if(game_ended?,
            do:
              selected_or_winning_player_id(
                final_players,
                final_player_order,
                socket.assigns.selected_player_id
              ),
            else: nil
          ),
        round_count: snapshot.round_count,
        game_variant: snapshot.game_variant,
        teams: snapshot.teams,
        team_scores: Map.get(snapshot, :team_scores, %{}),
        team_gains: Map.get(snapshot, :team_gains, %{}),
        team_drawers: Map.get(snapshot, :team_drawers, []),
        word_picker_id: Map.get(snapshot, :word_picker_id),
        team_finished?: Map.get(snapshot, :team_finished?, false),
        can_guess?: snapshot.can_guess?,
        constraint: snapshot.constraint,
        spin_holder: snapshot.spin_holder,
        spin_available?: snapshot.spin_available?,
        spin_started_at: snapshot.spin_started_at,
        current_round: snapshot.current_round,
        word_choices: snapshot.word_choices,
        word_list_label:
          if(snapshot.word_list != :default,
            do:
              Enum.find_value(Words.word_list_options(), fn {label, id} ->
                if id == snapshot.word_list, do: label
              end)
          ),
        turn_end_time: snapshot.turn_end_time,
        word: snapshot.word,
        show_word: snapshot.word_visible?,
        correct_guesses: snapshot.correct_guesses,
        drawing_vote: snapshot.drawing_vote,
        revealed_indices: snapshot.revealed_indices,
        feed_ids: MapSet.new(snapshot.feed, & &1.id),
        score_gains: snapshot.score_gains
      )

    socket = stream(socket, :feed, new_feed)

    socket =
      if snapshot.turn_end_time && snapshot.phase in [:word_choice, :playing, :turn_reveal] &&
           (initial? || old_phase != snapshot.phase || old_turn_end_time != snapshot.turn_end_time) do
        push_event(socket, "set_timer", %{end_time: DateTime.to_iso8601(snapshot.turn_end_time)})
      else
        socket
      end

    drawing_visible? = snapshot.phase in [:playing, :turn_reveal]
    drawing_was_visible? = old_phase in [:playing, :turn_reveal]

    socket =
      if not initial? and drawing_visible? do
        Enum.reduce(new_feed, socket, fn entry, socket ->
          if entry.kind in [:like, :dislike] and Map.get(entry, :own_drawing?, true) do
            push_event(socket, "drawing_vote", %{
              vote: if(entry.kind == :like, do: "up", else: "down")
            })
          else
            socket
          end
        end)
      else
        socket
      end

    socket =
      if drawing_visible? && (initial? || not drawing_was_visible?) do
        push_event(socket, "drawing_state", %{
          events: snapshot.current_drawing,
          server_now: System.system_time(:millisecond)
        })
      else
        socket
      end

    socket =
      if initial? or old_phase != snapshot.phase, do: sync_round_audio(socket), else: socket

    socket =
      if not initial? and snapshot.phase != :game_ended and map_size(snapshot.players) > old_count,
        do: push_event(socket, "play_sound", %{sound: "join"}),
        else: socket

    case if(initial?, do: [], else: MapSet.to_list(newly_correct)) do
      [player_id | _] ->
        sound = if player_id == snapshot.viewer_id, do: "correctGuess", else: "otherPlayerCorrect"
        push_event(socket, "play_sound", %{sound: sound})

      [] ->
        socket
    end
  end
end
