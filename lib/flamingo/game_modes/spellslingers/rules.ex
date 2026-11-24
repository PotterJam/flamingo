defmodule Flamingo.GameModes.Spellslingers.Rules do
  @moduledoc """
  Tuning numbers shared by every part of the Spellslingers engine. Each engine
  module `use`s this so the numbers are compile-time constants that can appear in
  guards and patterns.
  """

  # Numbers an allowlisted player can change mid-game from the arena's dev
  # panel. Each game copies the defaults into `state.tuning`.
  @tuning [
    %{key: :gravity, label: "Gravity", default: 38.0, min: 5, max: 90, step: 1},
    %{key: :wind_accel, label: "Wind strength", default: 1.6, min: 0, max: 6, step: 0.1},
    %{key: :damage_pct, label: "Damage %", default: 100, min: 25, max: 400, step: 5},
    %{key: :walk_budget, label: "Walk per turn", default: 40, min: 0, max: 200, step: 5},
    %{key: :fall_safe, label: "Safe fall height", default: 8, min: 0, max: 60, step: 1},
    # How far from the caster a placed spell (a slab) may appear.
    %{key: :place_range, label: "Place range", default: 70, min: 10, max: 250, step: 5},
    %{key: :crate_chance, label: "Crate chance", default: 0.35, min: 0, max: 1, step: 0.05},
    %{key: :max_crates, label: "Max crates", default: 4, min: 0, max: 12, step: 1},
    %{key: :surge_chance, label: "Wild magic chance", default: 0.22, min: 0, max: 1, step: 0.05}
  ]

  def clamp(value, low, high), do: value |> max(low) |> min(high)

  def tuning, do: @tuning
  def default_tuning, do: Map.new(@tuning, &{&1.key, &1.default})

  defmacro __using__(_opts) do
    quote do
      import Flamingo.GameModes.Spellslingers.Rules, only: [clamp: 3]

      # The world is wider than one screen; the client's camera pans across it.
      @width 300
      @height 110
      @initial_water @height - 6
      # Map shapes are drawn on a 200 x 100 canvas. Hand-drawn ones sit centred with
      # @margin cells of open land either side, and @sky rows of open air sit above.
      @margin div(@width - 200, 2)
      @sky @height - 100
      @wizard_hp 100
      @max_climb 2
      # Jumps, as in Arcanists: a high jump goes up and a little forward, a long jump
      # low and far. Each is {apex height, distance over flat ground} in cells, and
      # spends @jump_cost of the turn's walking steps.
      @jumps %{high: {10, 6}, long: {4, 18}}
      @jump_cost 5
      # Cells a broomstick flies, in any direction, before it is spent.
      @broom_fuel 80
      # After a cast the wizard gets a few seconds to run, as in Worms.
      @retreat_ms 4000
      @bot_retreat_ms 1500
      # How long a bot's aim sweeps across the screen before it lets fly.
      @bot_aim_ms 1300
      @dt 0.04
      @max_speed 78.0
      @max_steps 450
      @playback_speed 1.6
      # How long a grand spell's title card plays before its effects.
      @grand_intro_ms 1300
      @max_bots 5
      @bot_think_ms 1400
      @bot_names ~w(Merlina Grimble Zephyra Thornwick Pyrrha)

      @palette ~w(#ef4444 #3b82f6 #22c55e #f59e0b #a855f7 #ec4899 #14b8a6 #f97316)
    end
  end
end
