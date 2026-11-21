defmodule Flamingo.GameModes.Spellslingers.Rules do
  @moduledoc """
  Tuning numbers shared by every part of the Spellslingers engine. Each engine
  module `use`s this so the numbers are compile-time constants that can appear in
  guards and patterns.
  """

  defmacro __using__(_opts) do
    quote do
      # The world is wider than one screen; the client's camera pans across it.
      @width 300
      @height 110
      @initial_water @height - 6
      # Map shapes are drawn on a 200 x 100 canvas. Hand-drawn ones sit centred with
      # @margin cells of open land either side, and @sky rows of open air sit above.
      @margin div(@width - 200, 2)
      @sky @height - 100
      @wizard_hp 100
      @walk_budget 40
      @max_climb 2
      @dt 0.04
      @gravity 38.0
      @max_speed 78.0
      @wind_accel 1.6
      @max_steps 450
      @playback_speed 1.6
      @fall_safe 8
      # How far from the caster a placed spell (wall, ledge, summon, bloom) may land.
      @place_range 70
      @max_minions 2
      @max_crates 4
      @book_ms 25_000
      @max_bots 5
      @bot_think_ms 1400
      @bot_names ~w(Merlina Grimble Zephyra Thornwick Pyrrha)

      @palette ~w(#ef4444 #3b82f6 #22c55e #f59e0b #a855f7 #ec4899 #14b8a6 #f97316)
    end
  end
end
