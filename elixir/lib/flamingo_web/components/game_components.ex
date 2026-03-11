defmodule FlamingoWeb.GameComponents do
  use Phoenix.Component

  attr :class, :any, default: nil
  slot :inner_block, required: true

  def card(assigns) do
    ~H"""
    <div class={[
      "rounded-base border-2 border-border bg-background shadow-shadow",
      @class
    ]}>
      {render_slot(@inner_block)}
    </div>
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
end
