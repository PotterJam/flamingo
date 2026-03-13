defmodule FlamingoWeb.GameComponents do
  use Phoenix.Component

  import FlamingoWeb.CoreComponents, only: [icon: 1]

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

      <div class="flex gap-1">
        <button
          :for={size <- [6, 9, 15]}
          data-size={size}
          class="flex h-10 w-10 cursor-pointer items-center justify-center border-2 border-border bg-white shadow-shadow active:translate-x-box-shadow-x active:translate-y-box-shadow-y active:shadow-none"
        >
          <div
            class="rounded-full bg-black"
            style={"width: #{size * 2}px; height: #{size * 2}px"}
          >
          </div>
        </button>
      </div>

      <div class="flex gap-1">
        <button
          data-tool="pen"
          class="flex h-10 w-10 cursor-pointer items-center justify-center border-2 border-border bg-white shadow-shadow active:translate-x-box-shadow-x active:translate-y-box-shadow-y active:shadow-none"
        >
          <.icon name="hero-paint-brush" class="h-5 w-5" />
        </button>
        <button
          data-tool="fill"
          class="flex h-10 w-10 cursor-pointer items-center justify-center border-2 border-border bg-white shadow-shadow active:translate-x-box-shadow-x active:translate-y-box-shadow-y active:shadow-none"
        >
          <.icon name="hero-arrows-pointing-in" class="h-5 w-5" />
        </button>
      </div>

      <div class="flex gap-1">
        <button
          data-action="undo"
          class="flex h-10 w-10 cursor-pointer items-center justify-center border-2 border-border bg-white shadow-shadow active:translate-x-box-shadow-x active:translate-y-box-shadow-y active:shadow-none"
        >
          <.icon name="hero-arrow-uturn-left" class="h-5 w-5" />
        </button>
        <button
          data-action="redo"
          class="flex h-10 w-10 cursor-pointer items-center justify-center border-2 border-border bg-white shadow-shadow active:translate-x-box-shadow-x active:translate-y-box-shadow-y active:shadow-none"
        >
          <.icon name="hero-arrow-uturn-right" class="h-5 w-5" />
        </button>
        <button
          data-action="clear"
          class="flex h-10 w-10 cursor-pointer items-center justify-center border-2 border-border bg-white shadow-shadow active:translate-x-box-shadow-x active:translate-y-box-shadow-y active:shadow-none"
        >
          <.icon name="hero-trash" class="h-5 w-5" />
        </button>
      </div>
    </div>
    """
  end
end
