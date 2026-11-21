defmodule FlamingoWeb.GameModes.Teams do
  use FlamingoWeb.GameModes.ScribbleFamily,
    id: :coop,
    title: "Teams",
    description:
      "Race in pairs, with one trio for odd numbers. Teams take turns picking a word that every team draws.",
    theme: %{
      selected: "bg-green-400",
      hover: "hover:bg-green-400",
      lobby: "bg-green-100",
      game: "bg-green-100",
      game_text: "text-green-300",
      banner: "TEAMS"
    },
    engine: Flamingo.GameModes.Coop
end
