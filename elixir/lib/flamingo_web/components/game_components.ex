defmodule FlamingoWeb.GameComponents do
  use Phoenix.Component

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

  @num_rows 30
  @num_cols 45
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
      flamin<span class="text-sky-400">go</span>
    </h1>
    """
  end

  attr :word, :string, default: "_ _ _ _ _"

  def game_header(assigns) do
    ~H"""
    <.box class="bg-pink-400 p-3">
      <div class="flex items-center justify-center">
        <p class="text-xl font-bold tracking-widest text-white">{@word}</p>
      </div>
    </.box>
    """
  end

  attr :players, :map, required: true
  attr :player_order, :list, required: true
  attr :drawer_id, :string, default: nil

  def player_list_panel(assigns) do
    ~H"""
    <.box class="flex w-full flex-1 flex-col bg-white p-0">
      <div class="min-h-0 flex-grow overflow-y-auto">
        <ul>
          <%= for pid <- @player_order do %>
            <li class={[
              "flex items-center gap-2 px-3 py-2",
              pid == @drawer_id && "bg-pink-100 font-semibold"
            ]}>
              <span class="inline-flex h-5 w-5 shrink-0 items-center justify-center">
                <%= if pid == @drawer_id do %>
                  <.icon name="hero-paint-brush" class="h-4 w-4" />
                <% end %>
              </span>
              <span class="truncate">{Map.get(@players, pid).name}</span>
            </li>
          <% end %>
        </ul>
      </div>
    </.box>
    """
  end

  @starburst_path "M96.4,8.1 L96.4,8.1 Q100.0,5.0 103.6,8.1 L120.5,22.7 Q124.1,25.8 128.9,25.4 L151.0,23.5 Q155.8,23.1 156.9,27.8 L162.0,49.5 Q163.1,54.2 167.2,56.7 L186.3,68.1 Q190.4,70.6 188.5,75.0 L179.9,95.6 Q178.0,100.0 179.9,104.4 L188.5,125.0 Q190.4,129.4 186.3,131.9 L167.2,143.3 Q163.1,145.8 162.0,150.5 L156.9,172.2 Q155.8,176.9 151.0,176.5 L128.9,174.6 Q124.1,174.2 120.5,177.3 L103.6,191.9 Q100.0,195.0 96.4,191.9 L79.5,177.3 Q75.9,174.2 71.1,174.6 L49.0,176.5 Q44.2,176.9 43.1,172.2 L38.0,150.5 Q36.9,145.8 32.8,143.3 L13.7,131.9 Q9.6,129.4 11.5,125.0 L20.1,104.4 Q22.0,100.0 20.1,95.6 L11.5,75.0 Q9.6,70.6 13.7,68.1 L32.8,56.7 Q36.9,54.2 38.0,49.5 L43.1,27.8 Q44.2,23.1 49.0,23.5 L71.1,25.4 Q75.9,25.8 79.5,22.7 Z"

  attr :position_class, :string, required: true
  attr :size_class, :string, default: "h-32 w-32"
  attr :text_class, :string, default: "text-3xl"
  attr :timer_id, :string, required: true
  attr :timer_hook, :string, required: true
  attr :end_time, :string, default: nil

  def starburst_timer(assigns) do
    assigns = assign(assigns, :path, @starburst_path)

    ~H"""
    <div class={@position_class}>
      <div class="relative flex items-center justify-center">
        <svg
          viewBox="0 0 200 200"
          xmlns="http://www.w3.org/2000/svg"
          class={["starburst", @size_class]}
        >
          <path d={@path} fill="#f9a8d4" />
        </svg>
        <span
          id={@timer_id}
          phx-hook={@timer_hook}
          phx-update="ignore"
          data-end-time={@end_time}
          class={["absolute font-timer font-black", @text_class]}
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
          <.icon name="hero-paint-brush" class="h-5 w-5" />
        </button>
        <button
          data-tool="fill"
          class="flex h-10 w-10 cursor-pointer items-center justify-center"
        >
          <.icon name="hero-arrows-pointing-out" class="h-5 w-5" />
        </button>
      </.button_group>

      <div class="flex gap-1">
        <button
          data-action="undo"
          class="flex h-8 w-8 cursor-pointer items-center justify-center hover:bg-pink-100"
        >
          <.icon name="hero-arrow-uturn-left" class="h-4 w-4" />
        </button>
        <button
          data-action="redo"
          class="flex h-8 w-8 cursor-pointer items-center justify-center hover:bg-pink-100"
        >
          <.icon name="hero-arrow-uturn-right" class="h-4 w-4" />
        </button>
        <button
          data-action="clear"
          class="flex h-8 w-8 cursor-pointer items-center justify-center hover:bg-pink-100"
        >
          <.icon name="hero-trash" class="h-4 w-4" />
        </button>
      </div>
    </div>
    """
  end
end
