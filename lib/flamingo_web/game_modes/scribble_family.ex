defmodule FlamingoWeb.GameModes.ScribbleFamily do
  @moduledoc """
  The take-turns-drawing modes played on the Scribble screen: rounds, a turn
  length and a word theme. A mode declares only what sets it apart:

      use FlamingoWeb.GameModes.ScribbleFamily,
        id: :constraint_roulette,
        title: "Roulette",
        description: "...",
        theme: %{...},
        engine_settings: %{game_variant: :constraint_roulette},
        spin: true

  `:engine` defaults to `Flamingo.GameModes.Scribble`; `:spin` offers the
  last-place spin; `:engine_settings` are added to every start.
  """
  use FlamingoWeb, :html

  alias FlamingoWeb.GameModes.SettingsFields

  defmacro __using__(opts) do
    quote bind_quoted: [opts: opts] do
      use FlamingoWeb.GameMode

      @family_opts opts

      def id, do: Keyword.fetch!(@family_opts, :id)
      def title, do: Keyword.fetch!(@family_opts, :title)
      def description, do: Keyword.fetch!(@family_opts, :description)
      def theme, do: Keyword.fetch!(@family_opts, :theme)
      def engine, do: Keyword.get(@family_opts, :engine, Flamingo.GameModes.Scribble)
      def live_view, do: FlamingoWeb.ScribbleLive
      def path(room_id, token), do: FlamingoWeb.GameModes.ScribbleFamily.path(room_id, token)

      def settings(assigns),
        do:
          FlamingoWeb.GameModes.ScribbleFamily.settings(
            Map.put(assigns, :spin?, Keyword.get(@family_opts, :spin, false))
          )

      def parse_settings(params),
        do:
          FlamingoWeb.GameModes.ScribbleFamily.parse_settings(
            params,
            Keyword.get(@family_opts, :spin, false),
            Keyword.get(@family_opts, :engine_settings, %{})
          )
    end
  end

  def path(room_id, token), do: ~p"/game/#{room_id}/scribble?resume_token=#{token}"

  attr :form, Phoenix.HTML.Form, required: true
  attr :spin?, :boolean, required: true

  def settings(assigns) do
    ~H"""
    <SettingsFields.rounds form={@form} />
    <SettingsFields.turn_length form={@form} />
    <SettingsFields.words form={@form} />
    <SettingsFields.spin :if={@spin?} form={@form} />
    """
  end

  def parse_settings(params, spin?, engine_settings) do
    with {:ok, words} <- SettingsFields.parse_words(params) do
      settings =
        words
        |> Map.merge(%{
          round_count: SettingsFields.parse_rounds(params),
          turn_length: SettingsFields.parse_turn_length(params)
        })
        |> Map.merge(if spin?, do: %{spin_enabled: SettingsFields.parse_spin(params)}, else: %{})
        |> Map.merge(engine_settings)

      {:ok, settings}
    end
  end
end
