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
      xmlns="http://www.w3.org/2000/svg"
    >
      <%!-- Feet --%>
      <g fill="none" stroke-linecap="round" stroke-linejoin="round">
        <g :if={@avatar["feet"] == 0} stroke-width="5">
          <path d="M45 134 L34 140 M45 134 L45 141 M83 134 L72 140 M83 134 L85 141" stroke="#111827" />
          <path
            d="M45 134 L34 140 M45 134 L45 141 M83 134 L72 140 M83 134 L85 141"
            stroke={@feet_color}
            stroke-width="2"
          />
        </g>
        <g :if={@avatar["feet"] == 1} fill={@feet_color} stroke="#111827" stroke-width="3">
          <path d="M45 131 Q28 132 29 141 Q39 145 51 139 Z" />
          <path d="M83 131 Q66 132 67 141 Q77 145 89 139 Z" />
        </g>
        <g :if={@avatar["feet"] == 2} fill={@feet_color} stroke="#111827" stroke-width="3">
          <ellipse cx="43" cy="137" rx="13" ry="6" /><ellipse cx="82" cy="137" rx="13" ry="6" />
        </g>
        <g :if={@avatar["feet"] == 3} fill={@feet_color} stroke="#111827" stroke-width="3">
          <ellipse cx="42" cy="137" rx="15" ry="7" /><ellipse cx="83" cy="137" rx="15" ry="7" />
          <path d="M35 135 L35 140 M42 134 L42 141 M76 135 L76 140 M83 134 L83 141" />
        </g>
        <g :if={@avatar["feet"] == 4} fill={@feet_color} stroke="#111827" stroke-width="3">
          <path d="M45 132 Q26 132 24 141 Q39 146 53 139 Z" />
          <path d="M83 132 Q64 132 62 141 Q77 146 91 139 Z" />
        </g>
      </g>

      <%!-- Legs --%>
      <g fill="none" stroke-linecap="round" stroke-linejoin="round">
        <g :if={@avatar["legs"] == 0}>
          <path d="M48 96 L45 134 M72 96 L83 134" stroke="#111827" stroke-width="8" />
          <path d="M48 96 L45 134 M72 96 L83 134" stroke={@legs_color} stroke-width="4" />
        </g>
        <g :if={@avatar["legs"] == 1}>
          <path d="M47 96 Q40 113 45 134 M73 96 Q80 113 83 134" stroke="#111827" stroke-width="12" />
          <path d="M47 96 Q40 113 45 134 M73 96 Q80 113 83 134" stroke={@legs_color} stroke-width="7" />
        </g>
        <g :if={@avatar["legs"] == 2}>
          <path d="M47 96 Q31 110 45 134 M73 96 Q96 109 83 134" stroke="#111827" stroke-width="14" />
          <path d="M47 96 Q31 110 45 134 M73 96 Q96 109 83 134" stroke={@legs_color} stroke-width="9" />
        </g>
        <g :if={@avatar["legs"] == 3}>
          <path d="M47 96 L40 116 L45 134 M73 96 L88 115 L83 134" stroke="#111827" stroke-width="12" />
          <path
            d="M47 96 L40 116 L45 134 M73 96 L88 115 L83 134"
            stroke={@legs_color}
            stroke-width="7"
          />
        </g>
        <g :if={@avatar["legs"] == 4}>
          <path d="M47 96 Q46 114 45 134 M73 96 Q82 113 83 134" stroke="#111827" stroke-width="10" />
          <path d="M47 96 Q46 114 45 134 M73 96 Q82 113 83 134" stroke={@legs_color} stroke-width="5" />
        </g>
      </g>

      <%!-- Body --%>
      <g stroke="#111827" stroke-width="4" stroke-linejoin="round">
        <g :if={@avatar["body"] == 0}>
          <path
            d="M28 72 L10 64 L18 82 Q22 103 62 105 Q94 105 103 82 Q86 65 55 65 Q37 65 28 72 Z"
            fill={@body_color}
          />
          <path
            d="M35 76 Q58 65 86 80 Q72 99 42 96 Z"
            fill="white"
            fill-opacity="0.3"
            stroke-width="3"
          />
        </g>
        <g :if={@avatar["body"] == 1}>
          <path d="M28 68 Q16 79 23 101 Q34 110 92 102 Q101 83 91 68 Z" fill={@body_color} />
          <path
            d="M38 70 L34 91 M58 68 L57 94 M79 70 L84 91"
            fill="none"
            stroke-width="3"
            opacity="0.45"
          />
        </g>
        <g :if={@avatar["body"] == 2}>
          <ellipse cx="60" cy="84" rx="45" ry="25" fill={@body_color} />
          <circle cx="35" cy="79" r="5" fill="white" fill-opacity="0.35" stroke="none" />
          <circle cx="77" cy="91" r="7" fill="white" fill-opacity="0.35" stroke="none" />
        </g>
        <g :if={@avatar["body"] == 3}>
          <ellipse cx="60" cy="83" rx="34" ry="31" fill={@body_color} />
          <ellipse cx="60" cy="88" rx="20" ry="19" fill="white" fill-opacity="0.3" stroke-width="3" />
          <circle cx="94" cy="77" r="10" fill="white" />
        </g>
        <g :if={@avatar["body"] == 4}>
          <path
            d="M18 75 Q31 56 72 63 Q97 66 105 84 Q93 105 55 105 Q22 104 18 75 Z"
            fill={@body_color}
          />
          <path
            d="M50 72 Q75 66 91 83 Q75 99 52 96 Q42 84 50 72 Z"
            fill="white"
            fill-opacity="0.3"
            stroke-width="3"
          />
        </g>
      </g>

      <%!-- Head --%>
      <g stroke="#111827" stroke-width="4" stroke-linecap="round" stroke-linejoin="round">
        <g :if={@avatar["head"] == 0}>
          <path d="M51 68 Q36 51 54 38" fill="none" stroke="#111827" stroke-width="19" />
          <path d="M51 68 Q36 51 54 38" fill="none" stroke={@head_color} stroke-width="13" />
          <circle cx="61" cy="29" r="20" fill={@head_color} />
          <circle cx="68" cy="25" r="5" fill="white" stroke-width="2" /><circle
            cx="69"
            cy="26"
            r="2"
            fill="#111827"
            stroke="none"
          />
          <path d="M78 25 Q100 19 111 28 Q100 39 78 36 Z" fill="#fb923c" stroke-width="3" />
          <path d="M99 23 Q109 24 111 28 Q104 37 98 38 Z" fill="#111827" stroke="none" />
        </g>
        <g :if={@avatar["head"] == 1}>
          <path
            d="M51 45 Q64 51 78 45 L80 73 Q65 79 48 72 Z"
            fill={@head_color}
            stroke="none"
          />
          <path
            d="M39 20 L43 4 L56 15 Q67 10 78 15 L91 5 L89 29 Q88 49 65 54 Q40 50 39 20 Z"
            fill={@head_color}
          />
          <circle cx="56" cy="29" r="3" fill="#111827" stroke="none" /><circle
            cx="75"
            cy="29"
            r="3"
            fill="#111827"
            stroke="none"
          />
          <path d="M61 37 Q66 41 71 37 M66 38 L66 43" fill="none" stroke-width="2.5" />
        </g>
        <g :if={@avatar["head"] == 2}>
          <ellipse cx="64" cy="34" rx="29" ry="21" fill={@head_color} />
          <circle cx="48" cy="14" r="10" fill={@head_color} /><circle
            cx="80"
            cy="14"
            r="10"
            fill={@head_color}
          />
          <circle cx="48" cy="14" r="4" fill="#111827" stroke="none" /><circle
            cx="80"
            cy="14"
            r="4"
            fill="#111827"
            stroke="none"
          />
          <path d="M52 39 Q64 48 76 39" fill="none" stroke-width="2.5" />
        </g>
        <g :if={@avatar["head"] == 3}>
          <ellipse cx="52" cy="14" rx="9" ry="22" fill={@head_color} transform="rotate(-8 52 14)" />
          <ellipse cx="77" cy="14" rx="9" ry="22" fill={@head_color} transform="rotate(8 77 14)" />
          <ellipse cx="64" cy="36" rx="26" ry="22" fill={@head_color} />
          <circle cx="55" cy="32" r="3" fill="#111827" stroke="none" /><circle
            cx="73"
            cy="32"
            r="3"
            fill="#111827"
            stroke="none"
          />
          <path d="M60 40 Q64 44 68 40" fill="none" stroke-width="2.5" />
        </g>
        <g :if={@avatar["head"] == 4}>
          <circle cx="61" cy="30" r="23" fill={@head_color} />
          <circle cx="54" cy="26" r="3" fill="#111827" stroke="none" /><circle
            cx="69"
            cy="26"
            r="3"
            fill="#111827"
            stroke="none"
          />
          <path d="M45 34 Q64 26 85 36 Q68 48 45 40 Z" fill="#fb923c" stroke-width="3" />
        </g>
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
    <div class="relative z-10 self-center">
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
          timer_hook="FlamingoWeb.ScribbleLive.Timer"
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
  attr :current_round, :integer, required: true
  attr :round_count, :integer, required: true

  def player_list_panel(assigns) do
    ~H"""
    <div class="relative z-10 flex w-full flex-1 flex-col">
      <p
        id="round-progress"
        class="absolute -top-8 left-1 text-xl leading-none font-black text-black"
      >
        Round {@current_round} of {@round_count}
      </p>
      <.box class="flex min-h-0 flex-1 flex-col bg-white p-0">
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
    </div>
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
