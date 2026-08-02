defmodule FlamingoWeb.GameComponents do
  use Phoenix.Component

  alias Flamingo.Avatar

  import FlamingoWeb.CoreComponents, only: [icon: 1, button_group: 1]

  attr :class, :any, default: nil
  slot :inner_block, required: true

  def box(assigns) do
    ~H"""
    <div class={[
      "rounded-base border-2 border-border shadow-shadow",
      @class
    ]}>
      {render_slot(@inner_block)}
    </div>
    """
  end

  attr :class, :any, default: nil
  slot :inner_block, required: true

  def card(assigns) do
    ~H"""
    <.box class={["bg-background", @class]}>
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
  # since the cells are a fixed-size tessellation behind a fixed full-screen
  # layer.
  @num_rows 66
  @num_cols 27
  @row_height_rem 2.5
  @col_width_rem 10

  @flamingo_cells (for row <- 0..(@num_rows - 1), col <- 0..(@num_cols - 1) do
                     offset = if rem(row, 2) != 0, do: @col_width_rem / 2, else: 0

                     %{
                       top: row * @row_height_rem,
                       left: col * @col_width_rem - offset - @col_width_rem,
                       row_class: if(rem(row, 2) == 0, do: "bg-row-even", else: "bg-row-odd")
                     }
                   end)

  def flamingo_background(assigns) do
    assigns = assign(assigns, :cells, @flamingo_cells)

    ~H"""
    <div class="fixed inset-0 -z-10 overflow-hidden bg-pink-200">
      <div class="relative h-full w-full">
        <span
          :for={cell <- @cells}
          class={[
            "font-retro-display absolute text-lg font-extrabold whitespace-nowrap text-pink-300 opacity-30 select-none",
            cell.row_class
          ]}
          style={"top: #{cell.top}rem; left: #{cell.left}rem"}
          aria-hidden="true"
        >
          flamingo
        </span>
      </div>
    </div>
    """
  end

  def logo(assigns) do
    ~H"""
    <h1 class="font-retro-display text-2xl font-bold text-pink-400">
      flamin<span class="text-purple-500">go</span>
    </h1>
    """
  end

  attr :avatar, :map, default: %{}
  attr :class, :any, default: nil
  attr :label, :string, default: "Flamingo avatar"

  def flamingo_avatar(assigns) do
    avatar = Avatar.normalize(assigns.avatar)
    body_colors = ~w(#f472b6 #fb7185 #c084fc #fb923c #2dd4bf #facc15)

    neck_paths = [
      "M51 80 C34 66 38 47 58 37",
      "M51 80 C72 64 33 51 58 37",
      "M51 80 C51 62 52 48 58 37",
      "M51 80 L38 64 L67 50 L58 37",
      "M51 80 C25 68 75 62 44 52 C31 47 43 37 58 37"
    ]

    tuft_paths = [
      [],
      ["M55 15 Q48 4 60 10"],
      ["M54 15 Q44 4 58 10", "M61 10 Q61 0 68 10"],
      ["M53 15 L51 1 L62 11", "M62 11 L69 0 L70 14"],
      ["M52 15 L44 3 L59 10", "M59 11 L63 0 L69 10", "M68 11 L79 3 L74 17"]
    ]

    assigns =
      assign(assigns,
        avatar: avatar,
        body_color: Enum.at(body_colors, avatar["body"]),
        neck_path: Enum.at(neck_paths, avatar["neck"]),
        beak_end: Enum.at([94, 101, 109, 118, 127], avatar["beak"]),
        eye_offset: Enum.at([0, 2, 4, 6, 8], avatar["eyes"]),
        tuft_paths: Enum.at(tuft_paths, avatar["tuft"])
      )

    ~H"""
    <svg
      viewBox="0 0 130 145"
      role="img"
      aria-label={@label}
      class={@class}
      xmlns="http://www.w3.org/2000/svg"
    >
      <path
        d={@neck_path}
        fill="none"
        stroke="#111827"
        stroke-width="19"
        stroke-linecap="round"
        stroke-linejoin="round"
      />
      <path
        d={@neck_path}
        fill="none"
        stroke={@body_color}
        stroke-width="14"
        stroke-linecap="round"
        stroke-linejoin="round"
      />

      <g fill="none" stroke-linecap="round" stroke-linejoin="round">
        <path d="M48 96 L47 135 L38 139" stroke="#111827" stroke-width="7" />
        <path d="M48 96 L47 135 L38 139" stroke={@body_color} stroke-width="3" />
        <path d="M68 96 L69 116 L83 124 L74 139" stroke="#111827" stroke-width="7" />
        <path d="M68 96 L69 116 L83 124 L74 139" stroke={@body_color} stroke-width="3" />
      </g>

      <path
        d="M28 77 L9 68 L17 84 Q20 102 52 105 Q79 107 94 88 Q83 68 55 67 Q37 67 28 77 Z"
        fill={@body_color}
        stroke="#111827"
        stroke-width="4"
        stroke-linejoin="round"
      />
      <path
        d="M31 78 Q53 68 78 81 Q67 99 41 98 Q32 92 31 78 Z"
        fill="white"
        fill-opacity="0.28"
        stroke="#111827"
        stroke-width="3"
      />
      <circle cx="65" cy="27" r="21" fill="#111827" />
      <circle cx="65" cy="27" r="18" fill={@body_color} />

      <path
        :for={path <- @tuft_paths}
        d={path}
        fill="none"
        stroke="#111827"
        stroke-width="5"
        stroke-linecap="round"
        stroke-linejoin="round"
      />

      <circle cx={67 + @eye_offset} cy="23" r="5.5" fill="white" stroke="#111827" stroke-width="2" />
      <circle cx={68 + @eye_offset} cy="24" r="2.3" fill="#111827" />

      <path
        d={"M79 23 Q#{@beak_end - 5} 18 #{@beak_end} 27 Q#{@beak_end - 2} 39 #{@beak_end - 11} 46 Q#{@beak_end - 9} 35 79 35 Z"}
        fill="#fb923c"
        stroke="#111827"
        stroke-width="3"
        stroke-linejoin="round"
      />
      <path
        d={"M#{@beak_end - 11} 22 Q#{@beak_end - 2} 20 #{@beak_end} 27 Q#{@beak_end - 2} 39 #{@beak_end - 11} 46 Q#{@beak_end - 8} 34 #{@beak_end - 11} 22 Z"}
        fill="#111827"
      />

      <g :if={@avatar["accessory"] == 1} stroke="#111827" stroke-width="3" stroke-linejoin="round">
        <path d="M49 13 L48 1 L57 8 L64 0 L70 9 L80 2 L77 15 Z" fill="#facc15" />
      </g>
      <g :if={@avatar["accessory"] == 2} stroke="#111827" stroke-width="3" stroke-linejoin="round">
        <path d="M49 43 Q36 36 38 52 Q42 59 51 49 Z" fill="#c084fc" />
        <path d="M52 43 Q63 36 62 51 Q59 58 50 49 Z" fill="#c084fc" />
        <circle cx="51" cy="47" r="4" fill="#facc15" />
      </g>
      <g :if={@avatar["accessory"] == 3} stroke="#111827" stroke-width="3">
        <ellipse cx="63" cy="12" rx="21" ry="7" fill="#c084fc" transform="rotate(-8 63 12)" />
        <path d="M64 7 Q68 1 73 4" fill="none" stroke-linecap="round" />
      </g>
      <g :if={@avatar["accessory"] == 4} fill="none" stroke="#111827" stroke-width="3">
        <circle cx={67 + @eye_offset} cy="23" r="8" />
        <path d={"M#{75 + @eye_offset} 23 L82 25"} />
      </g>
      <g :if={@avatar["accessory"] == 5} stroke="#111827" stroke-width="2">
        <circle cx="49" cy="20" r="6" fill="#facc15" />
        <circle cx="49" cy="10" r="6" fill="#fb7185" />
        <circle cx="58" cy="16" r="6" fill="#fb7185" />
        <circle cx="55" cy="26" r="6" fill="#fb7185" />
        <circle cx="43" cy="26" r="6" fill="#fb7185" />
        <circle cx="40" cy="16" r="6" fill="#fb7185" />
      </g>
    </svg>
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
          revealed = MapSet.new(assigns.revealed_indices)

          chars =
            word
            |> String.graphemes()
            |> Enum.with_index()
            |> Enum.map(fn {ch, idx} ->
              if ch == " " or MapSet.member?(revealed, idx), do: ch, else: "_"
            end)

          count =
            word
            |> String.split(" ")
            |> Enum.map(&String.length/1)
            |> Enum.join("-")

          {word, chars, count}
      end

    assigns =
      assign(assigns, display: display, hint_chars: hint_chars, letter_count: letter_count)

    ~H"""
    <div class="relative self-center">
      <div class={[
        "rounded-full border-2 border-border bg-pink-400 px-10 pt-1 pb-4 shadow-rounded",
        if(!@display, do: "invisible")
      ]}>
        <div class="flex items-center justify-center gap-4">
          <%= if @hint_chars do %>
            <p class="flex items-baseline gap-[0.18em] font-hero text-5xl leading-none font-black text-white">
              <span
                :for={ch <- @hint_chars}
                class={["inline-block text-center", ch == " " && "w-[0.45em]"]}
              >
                {if(ch == " ", do: "", else: ch)}
              </span>
            </p>
          <% else %>
            <p class="font-hero text-5xl leading-none font-black tracking-widest text-white">
              {if(@display, do: @display, else: Phoenix.HTML.raw("&nbsp;"))}
            </p>
          <% end %>
          <%= if @hint_chars && @letter_count do %>
            <p class="font-hero text-2xl leading-none font-bold text-white">{@letter_count}</p>
          <% end %>
        </div>
      </div>
      <%= if @show_timer do %>
        <.starburst_timer
          position_class="absolute -top-4 -right-20 rotate-12"
          size_class="h-24 w-24"
          text_class="text-2xl"
          timer_id="turn-timer"
          timer_hook="FlamingoWeb.GameLive.Timer"
          end_time={@turn_end_time && DateTime.to_iso8601(@turn_end_time)}
          stroke="black"
          stroke_width="6"
        />
      <% end %>
    </div>
    """
  end

  attr :players, :map, required: true
  attr :player_order, :list, required: true
  attr :drawer_id, :string, default: nil
  attr :correct_guesses, :any, default: MapSet.new()

  def player_list_panel(assigns) do
    ~H"""
    <.box class="flex w-full flex-1 flex-col bg-white p-0">
      <div id="player-list-scroll" class="min-h-0 flex-grow overflow-y-auto overflow-x-hidden">
        <ul>
          <%= for pid <- @player_order do %>
            <% connected = Map.get(Map.get(@players, pid), :connected, true) %>
            <li
              id={"player-row-#{pid}"}
              class={[
                "flex min-w-0 items-center gap-2 px-3 py-2 transition-opacity",
                pid == @drawer_id && "bg-pink-100 font-semibold",
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
                  <% pid == @drawer_id -> %>
                    <.icon name={:paintbrush} class="h-4 w-4" />
                  <% MapSet.member?(@correct_guesses, pid) -> %>
                    <.icon name={:check} class="h-4 w-4 text-green-600" />
                  <% true -> %>
                <% end %>
              </span>
              <span class="min-w-0 flex-1 truncate">{Map.get(@players, pid).name}</span>
              <span class="shrink-0 text-sm font-semibold">{Map.get(@players, pid).score}</span>
            </li>
          <% end %>
        </ul>
      </div>
    </.box>
    """
  end

  attr :position_class, :string, required: true
  attr :size_class, :string, default: "h-32 w-32"
  attr :text_class, :string, default: "text-3xl"
  attr :timer_id, :string, required: true
  attr :timer_hook, :string, required: true
  attr :end_time, :string, default: nil
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
            fill="#f9a8d4"
            stroke={@stroke}
            stroke-width={@stroke_width}
          />
        </svg>
        <span
          id={@timer_id}
          phx-hook={@timer_hook}
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
