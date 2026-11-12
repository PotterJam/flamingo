defmodule FlamingoWeb.GameComponents do
  use Phoenix.Component

  alias Flamingo.Avatar

  import FlamingoWeb.CoreComponents, only: [button: 1, button_group: 1, icon: 1, input: 1]

  attr :class, :any, default: nil
  attr :radius, :string, default: nil, doc: "Optional CSS border radius, such as 30px or 2rem"
  attr :rest, :global
  slot :inner_block, required: true

  def box(assigns) do
    ~H"""
    <div
      class={[
        "rounded-base border-2 border-border shadow-shadow",
        @class
      ]}
      style={@radius && "border-radius: #{@radius}"}
      {@rest}
    >
      {render_slot(@inner_block)}
    </div>
    """
  end

  attr :class, :any, default: nil
  attr :radius, :string, default: nil, doc: "Optional CSS border radius, forwarded to the box"
  attr :rest, :global
  slot :inner_block, required: true

  def card(assigns) do
    ~H"""
    <.box class={["bg-background", @class]} radius={@radius} {@rest}>
      {render_slot(@inner_block)}
    </.box>
    """
  end

  attr :class, :any, default: nil

  def separator(assigns) do
    ~H"""
    <hr class={["border-t-2 border-border", @class]} />
    """
  end

  # Rows must cover the tallest realistic viewport (portrait QHD ~2560 CSS px)
  # and columns the widest (4K ~3840 CSS px plus drift animation overshoot),
  # including the off-screen start of each animated row.
  @num_rows 66
  @num_cols 27
  @row_height_rem 2.5

  @flamingo_rows (for row <- 0..(@num_rows - 1) do
                    %{
                      top: row * @row_height_rem,
                      left: if(rem(row, 2) == 0, do: -10, else: -15),
                      mode_row?: rem(row, 2) != 0,
                      row_class: if(rem(row, 2) == 0, do: "bg-row-even", else: "bg-row-odd")
                    }
                  end)

  attr :game_mode, :atom,
    default: :classic,
    values: [:classic, :constraint_roulette, :telephone, :coop]

  attr :label, :string, default: "SCRIBBLE"

  def flamingo_background(assigns) do
    {background_class, word_class} = flamingo_background_classes(assigns.game_mode)

    assigns =
      assign(assigns,
        rows: @flamingo_rows,
        repetitions: @num_cols,
        background_class: background_class,
        word_class: word_class
      )

    ~H"""
    <div
      id="flamingo-background"
      data-game-mode={@game_mode}
      class={["fixed inset-0 -z-10 overflow-hidden", @background_class]}
    >
      <div class="relative h-full w-full">
        <div
          :for={row <- @rows}
          class={[
            "font-retro-display absolute flex w-max gap-4 text-lg font-extrabold whitespace-nowrap opacity-30 select-none",
            @word_class,
            row.row_class
          ]}
          style={"top: #{row.top}rem; left: #{row.left}rem"}
          aria-hidden="true"
        >
          <span :for={_ <- 1..@repetitions}>
            {if row.mode_row?, do: @label, else: "FLAMINGO"}
          </span>
        </div>
      </div>
    </div>
    """
  end

  defp flamingo_background_classes(:constraint_roulette),
    do: {"bg-purple-100", "text-purple-300"}

  defp flamingo_background_classes(:telephone), do: {"bg-sky-100", "text-sky-300"}
  defp flamingo_background_classes(:coop), do: {"bg-green-100", "text-green-300"}
  defp flamingo_background_classes(_game_mode), do: {"bg-pink-200", "text-pink-300"}

  def logo(assigns) do
    ~H"""
    <h1 class="font-retro-display text-2xl font-bold text-pink-400">
      flamin<span class="text-purple-500">go</span>
    </h1>
    """
  end

  # Each animal's traced parts, keyed by {part, animal index}. Regenerate them with
  # `uv run assets/avatar/trace_parts.py`.
  @avatar_parts_dir Path.expand("../../../priv/avatar_parts", __DIR__)
  @avatar_parts (for {animal, index} <- Avatar.animals(), part <- Avatar.parts(), into: %{} do
                   path = Path.join([@avatar_parts_dir, animal, "#{part}.svg"])
                   @external_resource path
                   {{part, index}, File.read!(path)}
                 end)

  attr :avatar, :map, default: %{}
  attr :class, :any, default: nil
  attr :label, :string, default: "Creature avatar"

  def flamingo_avatar(assigns) do
    avatar = Avatar.normalize(assigns.avatar)

    assigns =
      assign(assigns,
        avatar: avatar,
        head_color: Avatar.color(avatar["head_color"]),
        body_color: Avatar.color(avatar["body_color"]),
        legs_color: Avatar.color(avatar["legs_color"]),
        feet_color: Avatar.color(avatar["feet_color"])
      )

    ~H"""
    <svg
      viewBox="0 0 130 145"
      role="img"
      aria-label={@label}
      class={@class}
      style={"--h: #{@head_color}; --b: #{@body_color}; --l: #{@legs_color}; --f: #{@feet_color}"}
      xmlns="http://www.w3.org/2000/svg"
    >
      <%!-- Drawn back to front, so legs cover the feet and the head's neck covers the body --%>
      <g :for={part <- ~w(feet legs body head)} data-avatar-part-root={part}>
        <%= if @avatar["#{part}_drawing"] == "" do %>
          {avatar_part(part, @avatar[part])}
        <% else %>
          <.avatar_drawing
            drawing={@avatar["#{part}_drawing"]}
            color={"var(--#{String.first(part)})"}
            default_width={if part == "feet", do: 4, else: 6}
          />
        <% end %>
      </g>
    </svg>
    """
  end

  defp avatar_part(part, index), do: Phoenix.HTML.raw(Map.fetch!(@avatar_parts, {part, index}))

  attr :drawing, :string, required: true
  attr :color, :string, required: true
  attr :default_width, :integer, default: 6

  defp avatar_drawing(assigns) do
    assigns =
      assign(assigns, :strokes, Avatar.drawing_strokes(assigns.drawing, assigns.default_width))

    ~H"""
    <g :for={stroke <- @strokes} fill="none" stroke-linecap="round" stroke-linejoin="round">
      <path d={stroke["path"]} stroke="#111827" stroke-width={stroke["width"] + 4} />
      <path d={stroke["path"]} stroke={@color} stroke-width={stroke["width"]} />
    </g>
    """
  end

  attr :word, :string, default: nil
  attr :show_word, :boolean, default: false
  attr :revealed_indices, :list, default: []
  attr :turn_end_time, :any, default: nil
  attr :show_timer, :boolean, default: false

  def game_header(assigns) do
    {display, hint_chars, letter_count} =
      case {assigns.word, assigns.show_word} do
        {nil, _} ->
          {nil, nil, nil}

        {word, true} ->
          {word, nil, nil}

        {word, false} ->
          chars =
            word
            |> Flamingo.Words.mask(assigns.revealed_indices)
            |> String.graphemes()

          count =
            word
            |> String.split([" ", "-"], trim: true)
            |> Enum.map(&String.length/1)
            |> Enum.join("-")

          {word, chars, count}
      end

    assigns =
      assign(assigns, display: display, hint_chars: hint_chars, letter_count: letter_count)

    ~H"""
    <div id="game-header" class="relative z-10 max-w-[calc(100%-10rem)] shrink-0 self-center">
      <div class={[
        "rounded-[2rem] border-2 border-border bg-pink-400 px-6 pt-1 pb-4 shadow-rounded sm:px-10",
        if(!@display, do: "invisible")
      ]}>
        <div class="flex flex-wrap items-center justify-center gap-x-4 gap-y-2">
          <%= if @hint_chars do %>
            <p
              id="game-word-hint"
              class={[
                "min-w-0 max-w-full text-center font-hero leading-tight font-black tracking-[0.18em] text-white [overflow-wrap:anywhere]",
                if(String.length(@display) > 30, do: "text-3xl", else: "text-5xl")
              ]}
            >
              {Enum.join(@hint_chars)}
            </p>
          <% else %>
            <p
              id="game-word-answer"
              class={[
                "min-w-0 max-w-full text-center font-hero leading-tight font-black tracking-widest text-white [overflow-wrap:anywhere]",
                if(@display && String.length(@display) > 30, do: "text-3xl", else: "text-5xl")
              ]}
            >
              {if(@display, do: @display, else: Phoenix.HTML.raw("&nbsp;"))}
            </p>
          <% end %>
          <%= if @hint_chars && @letter_count do %>
            <p
              id="game-word-lengths"
              class="max-w-full shrink-0 text-center font-hero text-2xl leading-none font-bold text-white [overflow-wrap:anywhere]"
            >
              {@letter_count}
            </p>
          <% end %>
        </div>
      </div>
      <%= if @show_timer do %>
        <.starburst_timer
          position_class="absolute -top-4 -right-20 rotate-12"
          size_class="h-24 w-24"
          text_class="text-2xl"
          timer_id="turn-timer"
          end_time={@turn_end_time && DateTime.to_iso8601(@turn_end_time)}
        />
      <% end %>
    </div>
    """
  end

  attr :players, :map, required: true
  attr :player_order, :list, required: true
  attr :teams, :map, default: %{}
  attr :team_scores, :map, default: %{}
  attr :team_drawers, :list, default: []
  attr :viewer_id, :string, default: nil
  attr :drawer_id, :string, default: nil
  attr :correct_guesses, :any, default: MapSet.new()
  attr :current_round, :integer, required: true
  attr :round_count, :integer, required: true

  def player_list_panel(assigns) do
    player_order =
      Enum.sort_by(assigns.player_order, fn pid -> -Map.fetch!(assigns.players, pid).score end)

    assigns =
      assign(
        assigns,
        :player_groups,
        player_order
        |> Enum.group_by(&Map.get(assigns.teams, &1))
        |> Enum.sort_by(fn {team, _players} ->
          {is_nil(team), -Map.get(assigns.team_scores, team, 0), team}
        end)
      )

    ~H"""
    <div class="relative z-10 flex w-full flex-1 flex-col">
      <.game_progress
        id="round-progress"
        label="Round"
        current={@current_round}
        total={@round_count}
      />
      <div
        id="player-list-scroll"
        class={[
          "-mr-1 -mb-1 min-h-0 flex-grow overflow-y-auto overflow-x-hidden pr-1 pb-1",
          @teams != %{} && "space-y-3"
        ]}
      >
        <.box
          :for={{team, player_order} <- @player_groups}
          class={["shrink-0 overflow-hidden bg-white p-0", @teams == %{} && "min-h-full"]}
        >
          <% own? = team != nil and team == @teams[@viewer_id] %>
          <h3
            :if={@teams != %{}}
            id={"team-title-#{team || "spectators"}"}
            data-own-team={to_string(own?)}
            class={[
              "flex items-center gap-2 border-b-2 border-border px-3 py-1 text-xs font-bold whitespace-nowrap",
              if(own?, do: "bg-pink-300", else: "bg-pink-100")
            ]}
          >
            {if team, do: "Team #{team}", else: "Spectators"}
            <span :if={team} class="ml-auto tabular-nums">{@team_scores[team]} pts</span>
          </h3>
          <ul id={if @teams != %{}, do: "team-players-#{team || "spectators"}", else: "player-list"}>
            <%= for pid <- player_order do %>
              <% connected = Map.get(Map.get(@players, pid), :connected, true) %>
              <li
                id={"player-row-#{pid}"}
                class={[
                  "flex min-w-0 items-center gap-2 px-3 py-2 transition-opacity",
                  (pid == @drawer_id or pid in @team_drawers) && "bg-pink-100 font-semibold",
                  pid != @drawer_id && MapSet.member?(@correct_guesses, pid) && "bg-green-100",
                  !connected && "opacity-40"
                ]}
              >
                <.flamingo_avatar
                  avatar={Map.get(Map.get(@players, pid), :avatar, %{})}
                  class="h-10 w-10 shrink-0"
                  label={"#{Map.get(@players, pid).name}'s avatar"}
                />
                <span class="inline-flex h-5 w-5 shrink-0 items-center justify-center">
                  <%= cond do %>
                    <% !connected -> %>
                      <.icon name={:wifi_off} class="h-4 w-4 text-gray-500" />
                    <% pid == @drawer_id or pid in @team_drawers -> %>
                      <.icon name={:paintbrush} class="h-4 w-4" />
                    <% MapSet.member?(@correct_guesses, pid) -> %>
                      <.icon name={:check} class="h-4 w-4 text-green-600" />
                    <% true -> %>
                  <% end %>
                </span>
                <span class="min-w-0 flex-1 truncate">{Map.get(@players, pid).name}</span>
                <span :if={@teams == %{}} class="shrink-0 text-sm font-semibold">
                  {Map.get(@players, pid).score}
                </span>
              </li>
            <% end %>
          </ul>
        </.box>
      </div>
    </div>
    """
  end

  attr :id, :string, required: true
  attr :label, :string, required: true
  attr :current, :integer, required: true
  attr :total, :integer, required: true
  attr :position_class, :string, default: "absolute -top-8 left-1"

  def game_progress(assigns) do
    ~H"""
    <p
      id={@id}
      class={[@position_class, "text-xl leading-none font-black text-black"]}
    >
      {@label} {@current} of {@total}
    </p>
    """
  end

  attr :choices, :list, required: true
  attr :id, :string, required: true
  attr :id_prefix, :string, required: true
  attr :event, :string, required: true
  attr :class, :any, default: nil

  def word_choice_buttons(assigns) do
    assigns = assign(assigns, :indexed_choices, Enum.with_index(assigns.choices))

    ~H"""
    <div id={@id} class={["flex flex-wrap justify-center gap-3", @class]}>
      <.button
        :for={{choice, index} <- @indexed_choices}
        id={"#{@id_prefix}-#{index}"}
        phx-click={@event}
        phx-value-choice={choice}
        class="px-6 py-3 text-base font-bold"
      >
        {choice}
      </.button>
    </div>
    """
  end

  attr :form, :map, required: true
  attr :field, :any, required: true
  attr :id, :string, required: true
  attr :input_id, :string, required: true
  attr :button_id, :string, required: true
  attr :submit, :string, required: true
  attr :placeholder, :string, required: true
  attr :button_label, :string, required: true
  attr :hook, :string, default: nil
  attr :mounted, :any, default: nil
  attr :maxlength, :integer, default: nil
  attr :class, :any, default: "w-96"
  slot :prefix

  def word_submission_form(assigns) do
    ~H"""
    <.form
      for={@form}
      phx-submit={@submit}
      phx-hook={@hook}
      id={@id}
      class={["relative z-10 mx-auto flex max-w-full items-center gap-2", @class]}
    >
      {render_slot(@prefix)}
      <div class="min-w-0 flex-1">
        <.input
          field={@field}
          type="text"
          placeholder={@placeholder}
          autocomplete="off"
          maxlength={@maxlength}
          phx-mounted={@mounted}
          class="w-full rounded-base border-2 border-border bg-white px-3 py-2 text-sm placeholder:text-gray-400 focus:ring-2 focus:ring-ring focus:ring-offset-2 focus:outline-none"
          id={@input_id}
        />
      </div>
      <.button type="submit" variant="default" id={@button_id}>
        {@button_label}
      </.button>
    </.form>
    """
  end

  attr :position_class, :string, required: true
  attr :size_class, :string, default: "h-32 w-32"
  attr :text_class, :string, default: "text-3xl"
  attr :timer_id, :string, required: true
  attr :end_time, :string, default: nil
  attr :fill, :string, default: "#f9a8d4"
  attr :stroke, :string, default: "none"
  attr :stroke_width, :string, default: "0"

  def starburst_timer(assigns) do
    ~H"""
    <div class={@position_class}>
      <div class="relative flex items-center justify-center">
        <svg
          viewBox="0 0 200 200"
          xmlns="http://www.w3.org/2000/svg"
          class={["starburst", @size_class]}
        >
          <path
            d="M96.4,8.1 L96.4,8.1 Q100.0,5.0 103.6,8.1 L120.5,22.7 Q124.1,25.8 128.9,25.4 L151.0,23.5 Q155.8,23.1 156.9,27.8 L162.0,49.5 Q163.1,54.2 167.2,56.7 L186.3,68.1 Q190.4,70.6 188.5,75.0 L179.9,95.6 Q178.0,100.0 179.9,104.4 L188.5,125.0 Q190.4,129.4 186.3,131.9 L167.2,143.3 Q163.1,145.8 162.0,150.5 L156.9,172.2 Q155.8,176.9 151.0,176.5 L128.9,174.6 Q124.1,174.2 120.5,177.3 L103.6,191.9 Q100.0,195.0 96.4,191.9 L79.5,177.3 Q75.9,174.2 71.1,174.6 L49.0,176.5 Q44.2,176.9 43.1,172.2 L38.0,150.5 Q36.9,145.8 32.8,143.3 L13.7,131.9 Q9.6,129.4 11.5,125.0 L20.1,104.4 Q22.0,100.0 20.1,95.6 L11.5,75.0 Q9.6,70.6 13.7,68.1 L32.8,56.7 Q36.9,54.2 38.0,49.5 L43.1,27.8 Q44.2,23.1 49.0,23.5 L71.1,25.4 Q75.9,25.8 79.5,22.7 Z"
            fill={@fill}
            stroke={@stroke}
            stroke-width={@stroke_width}
          />
        </svg>
        <span
          id={@timer_id}
          phx-hook="CountdownTimer"
          phx-update="ignore"
          data-end-time={@end_time}
          class={["absolute font-hero font-black", @text_class]}
          style="font-variant-numeric: tabular-nums; letter-spacing: 0.05em; min-width: 3ch; text-align: center;"
        >
        </span>
      </div>
    </div>
    """
  end

  attr :id, :string, required: true
  attr :is_drawer, :boolean, required: true
  attr :show_toolbar, :boolean, default: false
  attr :palette, :list, default: []
  attr :constraint, :any, default: nil
  attr :spin_started_at, :integer, default: nil
  attr :phase, :any, default: nil
  attr :class, :any, default: nil

  def drawing_canvas(assigns) do
    ~H"""
    <div
      id={@id}
      phx-hook="DrawingCanvas"
      phx-update="ignore"
      data-is-drawer={to_string(@is_drawer)}
      data-show-toolbar={to_string(@show_toolbar)}
      data-constraint={@constraint}
      data-phase={@phase}
      data-spin-started-at={@spin_started_at}
      class={["group/canvas relative flex w-[704px] max-w-full flex-col gap-2", @class]}
    >
      <span
        data-spin-status
        hidden
        role="status"
        class="pointer-events-none absolute inset-x-0 top-3 z-20 mx-auto w-fit rounded-base border-2 border-border bg-yellow-200 px-3 py-1 text-sm font-bold shadow-shadow"
      >
      </span>
      <.box class="drawing-canvas-frame relative z-0 bg-white p-0">
        <canvas
          width="700"
          height="500"
          class={[
            "block aspect-[7/5] w-full bg-white",
            if(@is_drawer, do: "cursor-crosshair", else: "cursor-default")
          ]}
        >
        </canvas>
        <div
          data-vote-flash
          aria-hidden="true"
          class="pointer-events-none absolute inset-0 z-10 opacity-0"
        >
        </div>
      </.box>

      <%= if @show_toolbar do %>
        <.box class="relative z-10 bg-white p-0 group-data-[show-toolbar=false]/canvas:hidden">
          <.drawing_toolbar palette={@palette} />
        </.box>
      <% end %>
    </div>
    """
  end

  attr :palette, :list, required: true

  def drawing_toolbar(assigns) do
    ~H"""
    <div class="flex w-full flex-row items-center justify-between gap-2 p-2">
      <div class="grid grid-cols-13 grid-rows-2 border-2 border-border">
        <button
          :for={color <- @palette}
          data-color={color}
          class="h-7 w-7 cursor-pointer"
          style={"background-color: #{color}"}
        >
        </button>
      </div>

      <.button_group>
        <button
          :for={size <- [6, 9, 15]}
          data-size={size}
          class="flex h-10 w-10 cursor-pointer items-center justify-center border-r-2 border-border last:border-r-0"
        >
          <div
            class="rounded-full bg-black"
            style={"width: #{size * 2}px; height: #{size * 2}px"}
          >
          </div>
        </button>
      </.button_group>

      <.button_group>
        <button
          data-tool="pen"
          class="flex h-10 w-10 cursor-pointer items-center justify-center border-r-2 border-border"
        >
          <.icon name={:paintbrush} class="h-5 w-5" />
        </button>
        <button
          data-tool="fill"
          class="flex h-10 w-10 cursor-pointer items-center justify-center"
        >
          <.icon name={:paint_bucket} class="h-5 w-5" />
        </button>
      </.button_group>

      <div class="flex">
        <button
          data-action="undo"
          class="flex h-8 w-8 cursor-pointer items-center justify-center hover:bg-pink-100"
        >
          <.icon name={:rotate_ccw} class="h-4 w-4" />
        </button>
        <button
          data-action="redo"
          class="flex h-8 w-8 cursor-pointer items-center justify-center hover:bg-pink-100"
        >
          <.icon name={:rotate_cw} class="h-4 w-4" />
        </button>
        <button
          data-action="clear"
          class="flex h-8 w-8 cursor-pointer items-center justify-center hover:bg-pink-100"
        >
          <.icon name={:trash} class="h-4 w-4" />
        </button>
      </div>
    </div>
    """
  end
end
