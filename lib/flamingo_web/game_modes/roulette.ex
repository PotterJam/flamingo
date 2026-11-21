defmodule FlamingoWeb.GameModes.Roulette do
  use FlamingoWeb.GameModes.ScribbleFamily,
    id: :constraint_roulette,
    title: "Roulette",
    description: "Like classic but with a little bit of spice",
    theme: %{
      selected: "bg-purple-400",
      hover: "hover:bg-purple-400",
      lobby: "bg-purple-100",
      game: "bg-purple-100",
      game_text: "text-purple-300",
      banner: "ROULETTE"
    },
    engine_settings: %{game_variant: :constraint_roulette},
    spin: true
end
