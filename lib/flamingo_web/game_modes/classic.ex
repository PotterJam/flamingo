defmodule FlamingoWeb.GameModes.Classic do
  use FlamingoWeb.GameModes.ScribbleFamily,
    id: :classic,
    title: "Classic",
    description: "Take turns drawing a word while everyone guesses",
    theme: %{
      selected: "bg-pink-300",
      hover: "hover:bg-pink-300",
      lobby: "bg-pink-100",
      game: "bg-pink-200",
      game_text: "text-pink-300",
      banner: "SCRIBBLE"
    },
    engine_settings: %{game_variant: :classic},
    spin: true
end
