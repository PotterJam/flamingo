defmodule FlamingoWeb.GameModes.Telephone do
  use FlamingoWeb.GameMode

  alias FlamingoWeb.GameModes.SettingsFields

  def id, do: :telephone
  def title, do: "Telephone"
  def description, do: "Cycle through guessing and drawing before revealing the chaos"

  def theme,
    do: %{
      selected: "bg-sky-400",
      hover: "hover:bg-sky-400",
      lobby: "bg-sky-100",
      game: "bg-sky-100",
      game_text: "text-sky-300",
      banner: "TELEPHONE"
    }

  def engine, do: Flamingo.GameModes.Telephone
  def live_view, do: FlamingoWeb.TelephoneLive
  def path(room_id, token), do: ~p"/game/#{room_id}/telephone?resume_token=#{token}"

  # Every player starts a chain, so the game length follows the player count.
  def settings(assigns) do
    ~H"""
    <SettingsFields.turn_length form={@form} />
    <SettingsFields.words form={@form} />
    """
  end

  def parse_settings(params) do
    with {:ok, words} <- SettingsFields.parse_words(params),
         do: {:ok, Map.put(words, :turn_length, SettingsFields.parse_turn_length(params))}
  end
end
