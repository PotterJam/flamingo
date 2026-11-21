defmodule FlamingoWeb.GameModes.Telephone do
  use FlamingoWeb.GameMode

  alias FlamingoWeb.GameModes.SettingsFields

  @impl true
  def id, do: :telephone
  @impl true
  def title, do: "Telephone"
  @impl true
  def description, do: "Cycle through guessing and drawing before revealing the chaos"

  @impl true
  def theme,
    do: %{
      selected: "bg-sky-400",
      hover: "hover:bg-sky-400",
      lobby: "bg-sky-100",
      game: "bg-sky-100",
      game_text: "text-sky-300",
      banner: "TELEPHONE"
    }

  @impl true
  def engine, do: Flamingo.GameModes.Telephone
  @impl true
  def live_view, do: FlamingoWeb.TelephoneLive
  @impl true
  def path(room_id, token), do: ~p"/game/#{room_id}/telephone?resume_token=#{token}"

  # Every player starts a chain, so the game length follows the player count.
  @impl true
  def settings(assigns) do
    ~H"""
    <SettingsFields.turn_length form={@form} />
    <SettingsFields.words form={@form} />
    """
  end

  @impl true
  def parse_settings(params) do
    with {:ok, words} <- SettingsFields.parse_words(params),
         do: {:ok, Map.put(words, :turn_length, SettingsFields.parse_turn_length(params))}
  end
end
