defmodule FlamingoWeb.GameModes.Spellslingers do
  use FlamingoWeb.GameMode

  alias Flamingo.GameModes.Spellslingers, as: Engine
  alias FlamingoWeb.GameModes.SettingsFields

  def id, do: :spellslingers
  def title, do: "Spells"

  def description,
    do: "Not a drawing game: wizards take turns hurling spells across a crumbling island"

  def theme,
    do: %{
      selected: "bg-amber-400",
      hover: "hover:bg-amber-400",
      lobby: "bg-amber-100",
      game: "bg-amber-100",
      game_text: "text-amber-300",
      banner: "SPELLSLINGERS"
    }

  # AI wizards can fill the arena, so one person can play alone.
  def min_players, do: 1

  def engine, do: Engine
  def live_view, do: FlamingoWeb.SpellslingersLive
  def path(room_id, token), do: ~p"/game/#{room_id}/spellslingers?resume_token=#{token}"

  @bot_range 1..Engine.max_bots()

  @arena_options [
    {"Random arena", "random"} | Enum.map(Engine.maps(), fn {id, name} -> {name, id} end)
  ]

  def settings(assigns) do
    ~H"""
    <SettingsFields.turn_length form={@form} label="Turn length(s)" />
    <div class="mb-4 space-y-1">
      <.input
        field={@form[:arena_map]}
        type="select"
        label="Arena"
        options={arena_options()}
        id="arena-map-select"
      />
    </div>
    <div class="mb-4 space-y-1">
      <.input
        field={@form[:bots]}
        type="select"
        label="AI wizards"
        options={bot_options()}
        id="arena-bots-select"
      />
    </div>
    """
  end

  defp arena_options, do: @arena_options
  defp bot_options, do: [{"None", "0"} | Enum.map(@bot_range, &{"#{&1}", "#{&1}"})]

  def parse_settings(params) do
    arena_ids = Enum.map(Engine.maps(), fn {id, _name} -> id end)
    arena = if params["arena_map"] in arena_ids, do: params["arena_map"], else: "random"

    bots =
      case Integer.parse(to_string(params["bots"])) do
        {n, ""} when n in @bot_range -> n
        _ -> 0
      end

    {:ok, %{turn_length: SettingsFields.parse_turn_length(params), arena_map: arena, bots: bots}}
  end
end
