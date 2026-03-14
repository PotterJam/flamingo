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

  attr :word, :string, default: nil
  attr :show_word, :boolean, default: false

  def game_header(assigns) do
    {display, letter_count} =
      case {assigns.word, assigns.show_word} do
        {nil, _} ->
          {nil, nil}

        {word, true} ->
          {word, nil}

        {word, false} ->
          hint = String.replace(word, ~r/[^ ]/, "_")

          count =
            word
            |> String.split(" ")
            |> Enum.map(&String.length/1)
            |> Enum.join("-")

          {hint, count}
      end

    assigns = assign(assigns, display: display, letter_count: letter_count)

    ~H"""
    <div class={[
      "self-center rounded-full border-2 border-border bg-pink-400 px-10 pt-1 pb-4 shadow-rounded",
      if(!@display, do: "invisible")
    ]}>
      <div class="flex items-center justify-center gap-4">
        <p class="font-timer text-5xl leading-none font-black tracking-widest text-white">
          {if(@display, do: @display, else: Phoenix.HTML.raw("&nbsp;"))}
        </p>
        <%= if @display && @letter_count do %>
          <p class="font-timer text-2xl leading-none font-bold text-white">{@letter_count}</p>
        <% end %>
      </div>
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
      <div class="min-h-0 flex-grow overflow-y-auto">
        <ul>
          <%= for pid <- @player_order do %>
            <li class={[
              "flex items-center gap-2 px-3 py-2",
              pid == @drawer_id && "bg-pink-100 font-semibold",
              pid != @drawer_id && MapSet.member?(@correct_guesses, pid) && "bg-green-100"
            ]}>
              <span class="inline-flex h-5 w-5 shrink-0 items-center justify-center">
                <%= cond do %>
                  <% pid == @drawer_id -> %>
                    <.icon name="paint_brush" class="h-4 w-4" />
                  <% MapSet.member?(@correct_guesses, pid) -> %>
                    <.icon name="check" class="h-4 w-4 text-green-600" />
                  <% true -> %>
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

  attr :position_class, :string, required: true
  attr :size_class, :string, default: "h-32 w-32"
  attr :text_class, :string, default: "text-3xl"
  attr :timer_id, :string, required: true
  attr :timer_hook, :string, required: true
  attr :end_time, :string, default: nil

  def starburst_timer(assigns) do
    ~H"""
    <div class={@position_class}>
      <div class="relative flex items-center justify-center">
        <img src="/images/starburst.svg" class={["starburst", @size_class]} />
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
          <.icon name="paint_brush" class="h-5 w-5" />
        </button>
        <button
          data-tool="fill"
          class="flex h-10 w-10 cursor-pointer items-center justify-center"
        >
          <.icon name="paint_bucket" class="h-5 w-5" />
        </button>
      </.button_group>

      <div class="flex">
        <button
          data-action="undo"
          class="flex h-8 w-8 cursor-pointer items-center justify-center hover:bg-pink-100"
        >
          <.icon name="arrow_counter_clockwise" class="h-4 w-4" />
        </button>
        <button
          data-action="redo"
          class="flex h-8 w-8 cursor-pointer items-center justify-center hover:bg-pink-100"
        >
          <.icon name="arrow_clockwise" class="h-4 w-4" />
        </button>
        <button
          data-action="clear"
          class="flex h-8 w-8 cursor-pointer items-center justify-center hover:bg-pink-100"
        >
          <.icon name="trash" class="h-4 w-4" />
        </button>
      </div>
    </div>
    """
  end
end
