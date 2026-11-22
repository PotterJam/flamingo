defmodule FlamingoWeb.GameHistoryComponents do
  @moduledoc """
  Shared UI components and formatting helpers for saved-lobby standings and
  game history pages.
  """

  use FlamingoWeb, :html

  alias Flamingo.GameModes.Spellslingers.Catalog, as: SpellsCatalog
  alias FlamingoWeb.GameModes

  @history_mode_ids [:classic, :constraint_roulette, :coop, :spellslingers]

  def history_modes, do: Enum.map(@history_mode_ids, &GameModes.get/1)

  def parse_mode_filter(param) when is_binary(param) do
    case GameModes.from_param(param) do
      nil -> nil
      mode -> if mode.id() in @history_mode_ids, do: mode.id()
    end
  end

  def parse_mode_filter(_), do: nil

  def rank_standings(standings) do
    Enum.map(standings, fn row ->
      Map.put(row, :rank, 1 + Enum.count(standings, &(&1.wins > row.wins)))
    end)
  end

  def format_score(nil), do: "0"

  def format_score(score) when is_integer(score) do
    score
    |> Integer.to_string()
    |> String.replace(~r/\B(?=(\d{3})+(?!\d))/, ",")
  end

  def format_date(%DateTime{} = dt, :full), do: Calendar.strftime(dt, "%A %-d %b, %H:%M")

  def format_date(%DateTime{} = dt, :short) do
    case Date.diff(Date.utc_today(), DateTime.to_date(dt)) do
      0 -> "Today, #{Calendar.strftime(dt, "%H:%M")}"
      1 -> "Yesterday"
      days when days in 2..6 -> "#{days} days ago"
      _ -> Calendar.strftime(dt, "%-d %b")
    end
  end

  def map_name(nil), do: nil

  def map_name(map_id) when is_binary(map_id) do
    case List.keyfind(SpellsCatalog.maps(), map_id, 0) do
      {^map_id, label} -> label
      nil -> map_id |> String.replace("_", " ") |> String.capitalize()
    end
  end

  def winner_display(%{mode: mode, players: players}) do
    winners = Enum.filter(players, &(&1.placement == 1))

    case {mode, winners} do
      {:spellslingers, []} ->
        {"Everyone fell", nil, true}

      {_, []} ->
        {"No winner", nil, true}

      {:coop, winners} ->
        score = format_points(hd(winners).score, "pts")

        names =
          case winners |> Enum.group_by(& &1.team) |> Enum.sort_by(&elem(&1, 0)) do
            [{_, members}] -> join_names(Enum.map(members, & &1.name))
            many -> join_names(Enum.map(many, &"Team #{elem(&1, 0)}"))
          end

        {names, score, false}

      {:spellslingers, [winner]} ->
        {winner.name, format_points(winner.score, "dmg"), false}

      {:spellslingers, many} ->
        {join_names(Enum.map(many, & &1.name)), nil, false}

      {_, [winner]} ->
        {winner.name, format_points(winner.score, "pts"), false}

      {_, many} ->
        {join_names(Enum.map(many, & &1.name)), format_points(hd(many).score, "pts"), false}
    end
  end

  defp format_points(score, unit) when is_integer(score), do: "#{format_score(score)} #{unit}"
  defp format_points(_, _), do: nil

  def guest?(%{user_id: nil, name: "Former player"}), do: false
  def guest?(%{user_id: nil}), do: true
  def guest?(_), do: false

  def former_player?(%{user_id: nil, name: "Former player"}), do: true
  def former_player?(_), do: false

  defp join_names([name]), do: name
  defp join_names([a, b]), do: "#{a} & #{b}"

  defp join_names(names) when length(names) <= 3 do
    {init, [last]} = Enum.split(names, -1)
    Enum.join(init, ", ") <> " & " <> last
  end

  defp join_names([a, b | rest]), do: "#{a}, #{b} + #{length(rest)} more"

  @mode_badge_colors %{
    classic: :pink,
    constraint_roulette: :purple,
    coop: :green,
    spellslingers: :amber
  }

  attr :mode, :atom, required: true

  def mode_badge(assigns) do
    assigns =
      assign(assigns,
        title: GameModes.get(assigns.mode).title(),
        color: Map.get(@mode_badge_colors, assigns.mode, :gray)
      )

    ~H"""
    <.badge color={@color} class="px-2.5">{@title}</.badge>
    """
  end

  attr :player, :map, required: true
  attr :avatar_class, :string, default: "size-10 shrink-0"
  attr :crown, :boolean, default: false

  def player_identity(assigns) do
    ~H"""
    <.flamingo_avatar
      :if={@player.user_id}
      avatar={(@player.user && @player.user.avatar) || %{}}
      class={@avatar_class}
      label={"#{@player.name}'s avatar"}
    />
    <span class={[
      "truncate font-bold",
      if(former_player?(@player), do: "italic text-gray-500", else: "text-black")
    ]}>
      {@player.name}
    </span>
    <.icon :if={@crown} name={:crown} class="size-4 shrink-0 text-amber-500" />
    <.badge :if={guest?(@player)} class="text-[0.7rem]">Guest</.badge>
    <.badge :if={is_nil(@player.placement)} class="text-[0.7rem]">Left early</.badge>
    """
  end

  attr :id, :string, default: "standings-table"
  attr :standings, :list, required: true
  attr :has_games?, :boolean, default: false
  attr :current_user_id, :string, default: nil

  def standings_podium(assigns) do
    ranked = rank_standings(assigns.standings)

    assigns =
      assign(assigns,
        top_three: Enum.take(ranked, 3),
        remaining: Enum.drop(ranked, 3)
      )

    ~H"""
    <div id={@id}>
      <p :if={@top_three == []} class="py-4 text-sm text-gray-600">
        {if @has_games?,
          do:
            "Only guests have played here so far. Sign in before joining to appear on the standings.",
          else: "No finished games yet. Finish a game in this lobby to start the standings."}
      </p>

      <div :if={@top_three != []}>
        <.podium id={"#{@id}-podium"} class="min-w-[20rem]" compact>
          <li
            :for={{row, idx} <- Enum.with_index(@top_three)}
            id={"#{@id}-row-#{row.user_id}"}
            value={row.rank}
            class={podium_slot_class(idx, compact: true)}
          >
            <div class="relative flex h-full w-full items-center justify-center">
              <span class={podium_label_class(idx, compact: true)}>
                <.flamingo_avatar
                  avatar={row.avatar || %{}}
                  class="size-8 shrink-0"
                  label={"#{row.name}'s avatar"}
                />
                <span class={[
                  "flex w-24 min-w-0 items-center text-sm sm:w-28",
                  idx == 1 && "justify-end text-right"
                ]}>
                  <span class="relative flex min-w-0 items-center gap-1.5">
                    <span class="min-w-0 truncate font-bold text-black" title={row.name}>
                      {row.name}
                    </span>
                    <span class="shrink-0 font-semibold tabular-nums text-pink-500">
                      {row.wins}
                    </span>
                  </span>
                </span>
              </span>
              <.podium_step rank={idx} label={row.rank} compact />
            </div>
          </li>
        </.podium>

        <ol
          :if={@remaining != []}
          id={"#{@id}-remaining"}
          start="4"
          class="max-h-36 overflow-y-auto pr-1"
        >
          <li
            :for={row <- @remaining}
            id={"#{@id}-row-#{row.user_id}"}
            class={[
              "flex min-w-0 items-center gap-2 rounded-base px-3 py-1 transition-colors hover:bg-pink-50",
              @current_user_id && row.user_id == @current_user_id && "bg-pink-100/70"
            ]}
          >
            <span class="w-5 shrink-0 text-sm font-bold tabular-nums text-gray-600">
              {row.rank}
            </span>
            <.flamingo_avatar
              avatar={row.avatar || %{}}
              class="size-8 shrink-0"
              label={"#{row.name}'s avatar"}
            />
            <span class="min-w-0 flex-1 truncate text-sm font-bold text-black">{row.name}</span>
            <.badge
              :if={@current_user_id && row.user_id == @current_user_id}
              color={:pink}
              class="text-[0.65rem]"
            >
              You
            </.badge>
            <span class="shrink-0 text-sm font-semibold tabular-nums text-pink-500">
              {row.wins}
            </span>
          </li>
        </ol>
      </div>
    </div>
    """
  end

  attr :game, :map, required: true
  attr :lobby_name, :string, required: true
  attr :id, :string, default: nil

  def game_summary_row(assigns) do
    {winner_name, points, muted?} = winner_display(assigns.game)

    assigns =
      assign(assigns,
        winner_name: winner_name,
        points: points,
        muted?: muted?,
        dom_id: assigns.id || "game-row-#{assigns.game.id}"
      )

    ~H"""
    <.link
      id={@dom_id}
      navigate={~p"/saved-lobby/#{@lobby_name}/history/#{@game.id}"}
      class="group flex items-center justify-between gap-3 rounded-base px-3 py-2 transition-colors hover:bg-pink-50 focus-visible:outline-2 focus-visible:outline-offset-2"
    >
      <div class="flex min-w-0 flex-wrap items-center gap-x-2 gap-y-1">
        <span class={[
          "truncate text-sm font-bold",
          if(@muted?, do: "italic text-gray-500", else: "text-black")
        ]}>
          {@winner_name}
        </span>
        <span :if={@points} class="shrink-0 text-sm font-semibold tabular-nums text-pink-500">
          {@points}
        </span>
        <.mode_badge mode={@game.mode} />
      </div>
      <div class="flex shrink-0 items-center gap-1.5 text-right">
        <time datetime={DateTime.to_iso8601(@game.finished_at)} class="text-sm text-gray-500">
          {format_date(@game.finished_at, :short)}
        </time>
        <.icon
          name={:chevron_right}
          class="size-4 shrink-0 text-gray-400 transition-transform group-hover:translate-x-0.5 group-hover:text-black"
        />
      </div>
    </.link>
    """
  end
end
